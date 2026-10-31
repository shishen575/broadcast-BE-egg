#!/bin/bash
# Runs inside the Pterodactyl container: playit tunnel + MCXboxBroadcast + BDS,
# with periodic update checks that announce in-game and restart.
cd /home/container || exit 1

PLAYIT_BIN=./playit
BROADCAST_JAR=./MCXboxBroadcastStandalone.jar
BDS_BIN=./bedrock_server
VDIR=.versions
CMD_FIFO=.bds_stdin
RESTART_FLAG=.restart_pending
ARCH=$(uname -m)
UA="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"

AUTO_UPDATE=${AUTO_UPDATE:-1}
UPDATE_INTERVAL=${UPDATE_INTERVAL:-60}   # minutes between checks
UPDATE_WARNING=${UPDATE_WARNING:-5}      # minutes of in-game notice before restart
UNIT=${UPDATE_SLEEP_UNIT:-60}            # seconds per "minute" (tests shrink this)

mkdir -p "$VDIR"
is_on() { case "${1,,}" in 1|true|yes|on) return 0 ;; esac; return 1; }
log() { printf '[egg] %s\n' "$*"; }
ver_get() { cat "$VDIR/$1" 2>/dev/null; }
ver_set() { printf '%s\n' "$2" > "$VDIR/$1"; }
send() { printf '%s\n' "$1" > "$CMD_FIFO"; }

# ---- latest versions -------------------------------------------------------
latest_bds_url() {
  curl -fsSL -H "Accept-Language: en" -H "User-Agent: $UA" \
    https://net-secondary.web.minecraft-services.net/api/v1.0/download/links \
    | jq -r '.result.links[] | select(.downloadType == "serverBedrockLinux") | .downloadUrl'
}

latest_gh_tag() {
  curl -fsSIL -o /dev/null -w '%{url_effective}' "https://github.com/$1/releases/latest" | sed 's|.*/tag/||'
}

# Prints the latest version id, or nothing when it cannot / should not be checked.
remote_version() {
  case $1 in
    bds) [ "${BEDROCK_VERSION:-latest}" = latest ] && latest_bds_url ;;
    playit) latest_gh_tag playit-cloud/playit-agent ;;
    broadcast) latest_gh_tag MiniDigger/MCXboxBroadcast ;;
  esac 2>/dev/null
}

enabled_components() {
  echo bds
  is_on "$USE_PLAYIT" && echo playit
  is_on "$USE_BROADCAST" && [ -n "${PUBLIC_ADDRESS}" ] && [ -n "${PUBLIC_PORT}" ] && echo broadcast
}

component_path() {
  case $1 in bds) echo "$BDS_BIN" ;; playit) echo "$PLAYIT_BIN" ;; broadcast) echo "$BROADCAST_JAR" ;; esac
}

# Components whose latest version differs from the installed one.
outdated_components() {
  local c r
  for c in $(enabled_components); do
    r=$(remote_version "$c")
    [ -n "$r" ] && [ "$r" != "$(ver_get "$c")" ] && echo "$c"
  done
}

# ---- installers ------------------------------------------------------------
install_bds() { # $1 = zip url
  local zip=bedrock-server.zip
  curl -fsSL -H "Accept-Language: en" -H "User-Agent: $UA" -o "$zip" "$1" || { rm -f "$zip"; return 1; }
  if [ -d worlds ]; then
    mkdir -p backups
    tar -czf "backups/worlds-$(date +%Y%m%d-%H%M%S).tar.gz" worlds
    ls -1t backups/worlds-*.tar.gz 2>/dev/null | tail -n +4 | xargs -r rm -f
  fi
  unzip -qo "$zip" -x server.properties allowlist.json permissions.json || { rm -f "$zip"; return 1; }
  rm -f "$zip"
  chmod +x "$BDS_BIN"
}

install_playit() {
  local asset=playit-linux-amd64
  [ "$ARCH" = aarch64 ] && asset=playit-linux-aarch64
  curl -fsSL -o "$PLAYIT_BIN.new" "https://github.com/playit-cloud/playit-agent/releases/latest/download/$asset" \
    && chmod +x "$PLAYIT_BIN.new" && mv "$PLAYIT_BIN.new" "$PLAYIT_BIN"
}

install_broadcast() {
  curl -fsSL -o "$BROADCAST_JAR.new" \
    "https://github.com/MiniDigger/MCXboxBroadcast/releases/latest/download/MCXboxBroadcastStandalone.jar" \
    && mv "$BROADCAST_JAR.new" "$BROADCAST_JAR"
}

# Install missing components; with AUTO_UPDATE also bring outdated ones up to date.
sync_components() {
  local c r need
  for c in $(enabled_components); do
    r=$(remote_version "$c")
    need=0
    [ -e "$(component_path "$c")" ] || need=1
    is_on "$AUTO_UPDATE" && [ -n "$r" ] && [ "$r" != "$(ver_get "$c")" ] && need=1
    [ "$need" = 1 ] && [ -n "$r" ] || continue
    log "$c をインストール中 ($r)"
    if [ "$c" = bds ]; then install_bds "$r"; else "install_$c"; fi \
      && ver_set "$c" "$r" || log "$c のインストールに失敗しました。現在のバージョンを使い続けます"
  done
}

# ---- broadcast config ------------------------------------------------------
write_broadcast_config() {
  mkdir -p broadcast && cd broadcast || return
  if [ ! -f config.yml ]; then
    cat > config.yml <<YML
session:
  update-interval: 30
  query-server: true
  web-query-fallback: false
  config-version: 2
  session-info:
    host-name: "${SERVER_NAME}"
    world-name: "${LEVEL_NAME}"
    version: "${BROADCAST_VERSION}"
    protocol: ${BROADCAST_PROTOCOL}
    players: 0
    max-players: ${MAX_PLAYERS}
    ip: "${PUBLIC_ADDRESS}"
    port: ${PUBLIC_PORT}
friend-sync:
  update-interval: 60
  auto-follow: true
  auto-unfollow: true
  initial-invite: true
  share-join-code: true
YML
  else
    # Keep the advertised address in sync with the panel variables.
    sed -i -E "s|^(\s*ip:).*|\1 \"${PUBLIC_ADDRESS}\"|; s|^(\s*port:).*|\1 ${PUBLIC_PORT}|" config.yml
  fi
  cd ..
}

# ---- helpers: tunnel, broadcaster ------------------------------------------
HELPER_PIDS=()
stop_helpers() {
  local p
  for p in "${HELPER_PIDS[@]}"; do kill "$p" 2>/dev/null; wait "$p" 2>/dev/null; done
  HELPER_PIDS=()
}

start_helpers() {
  if is_on "$USE_PLAYIT" && [ -x "$PLAYIT_BIN" ]; then
    local args=()
    [ -n "${PLAYIT_SECRET}" ] && args+=(--secret "${PLAYIT_SECRET}")
    log "playit トンネルを起動します(初回は下に表示される認証URLを開いてください)"
    "$PLAYIT_BIN" "${args[@]}" </dev/null &
    HELPER_PIDS+=($!)
  fi
  if is_on "$USE_BROADCAST"; then
    if [ -z "${PUBLIC_ADDRESS}" ] || [ -z "${PUBLIC_PORT}" ]; then
      log "フレンド参加用の broadcast をスキップしました: playit ダッシュボードのトンネルアドレスを PUBLIC_ADDRESS と PUBLIC_PORT に設定してください"
    elif [ -f "$BROADCAST_JAR" ]; then
      write_broadcast_config
      log "MCXboxBroadcast を起動します(初回は下に表示される Microsoft のコードでサインインしてください)"
      ( cd broadcast && exec java -Xmx256M -jar ../"$BROADCAST_JAR" ) </dev/null &
      HELPER_PIDS+=($!)
    fi
  fi
}

# ---- update watcher --------------------------------------------------------
update_watcher() {
  local pending w
  while sleep $((UPDATE_INTERVAL * UNIT)); do
    pending=$(outdated_components | tr '\n' ' ')
    [ -z "$pending" ] && continue
    log "アップデートがあります: $pending"
    w=$UPDATE_WARNING
    if [ "$w" -gt 0 ]; then
      send "say アップデートのため ${w} 分後にサーバーを再起動します"
      if [ "$w" -gt 1 ]; then
        sleep $(((w - 1) * UNIT))
        send "say アップデートのため 1 分後にサーバーを再起動します"
      fi
      sleep $((UNIT - 10 > 0 ? UNIT - 10 : 1))
      send "say 10 秒後に再起動します"
      sleep $((UNIT > 10 ? 10 : 1))
    fi
    log "アップデート適用のため再起動します"
    touch "$RESTART_FLAG"
    send "stop"
    return
  done
}

# ---- main ------------------------------------------------------------------
cleanup() {
  stop_helpers
  [ -n "$WATCHER_PID" ] && kill "$WATCHER_PID" 2>/dev/null
  [ -n "$FORWARD_PID" ] && kill "$FORWARD_PID" 2>/dev/null
  rm -f "$CMD_FIFO"
}
trap cleanup EXIT
trap 'exit 143' TERM INT

# BDS reads commands from a fifo so the panel console and the watcher can both write to it.
rm -f "$CMD_FIFO"; mkfifo "$CMD_FIFO"
exec 3<>"$CMD_FIFO"
exec 4<&0   # background jobs get /dev/null as stdin unless it is passed explicitly
cat <&4 >&3 &
FORWARD_PID=$!

export LD_LIBRARY_PATH=.
while true; do
  rm -f "$RESTART_FLAG"
  sync_components
  start_helpers
  if is_on "$AUTO_UPDATE"; then
    update_watcher &
    WATCHER_PID=$!
  fi

  "$BDS_BIN" <&3
  code=$?

  [ -n "$WATCHER_PID" ] && kill "$WATCHER_PID" 2>/dev/null
  WATCHER_PID=
  stop_helpers
  [ -f "$RESTART_FLAG" ] || exit "$code"
  log "アップデートのためサーバーを停止しました。再起動します"
done
