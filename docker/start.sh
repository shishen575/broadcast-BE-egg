#!/bin/bash
# Runs inside the Pterodactyl container: playit tunnel / frp client + MCXboxBroadcast + BDS,
# with periodic update checks that announce in-game and restart.
cd /home/container || exit 1

PLAYIT_BIN=./playit
FRPC_BIN=./frpc
BROADCAST_JAR=./MCXboxBroadcastStandalone.jar
BDS_BIN=./bedrock_server
PLAYIT_SOCK=/home/container/.playit.sock
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
    broadcast) latest_gh_tag rtm516/MCXboxBroadcast ;;
    frp) if [ -n "${FRP_VERSION}" ]; then echo "v${FRP_VERSION#v}"; else latest_gh_tag fatedier/frp; fi ;;
  esac 2>/dev/null
}

enabled_components() {
  echo bds
  is_on "$USE_PLAYIT" && echo playit
  is_on "$USE_BROADCAST" && echo broadcast
  is_on "$USE_FRP" && echo frp
}

component_path() {
  case $1 in bds) echo "$BDS_BIN" ;; playit) echo "$PLAYIT_BIN" ;; broadcast) echo "$BROADCAST_JAR" ;; frp) echo "$FRPC_BIN" ;; esac
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
    "https://github.com/rtm516/MCXboxBroadcast/releases/latest/download/MCXboxBroadcastStandalone.jar" \
    && mv "$BROADCAST_JAR.new" "$BROADCAST_JAR"
}

install_frp() { # $1 = tag such as v0.61.0
  local ver=${1#v} arch=amd64 tgz=frp.tar.gz
  [ "$ARCH" = aarch64 ] && arch=arm64
  curl -fsSL -o "$tgz" "https://github.com/fatedier/frp/releases/download/v${ver}/frp_${ver}_linux_${arch}.tar.gz" \
    || { rm -f "$tgz"; return 1; }
  tar -xzf "$tgz" --strip-components=1 --wildcards '*/frpc' || { rm -f "$tgz"; return 1; }
  rm -f "$tgz"
  chmod +x "$FRPC_BIN"
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
    "install_$c" "$r" \
      && ver_set "$c" "$r" || log "$c のインストールに失敗しました。現在のバージョンを使い続けます"
  done
}

# The playit tunnel only carries RakNet, but recent BDS versions default to NetherNet.
ensure_transport() {
  local t=${TRANSPORT:-raknet}
  if [ ! -f server.properties ]; then
    printf 'transport=%s\n' "$t" > server.properties
  elif grep -q '^transport=' server.properties; then
    sed -i "s|^transport=.*|transport=$t|" server.properties
  else
    printf '\ntransport=%s\n' "$t" >> server.properties
  fi
}

# ---- broadcast config ------------------------------------------------------
write_broadcast_config() {
  # Until the tunnel address is known, advertise "auto" so the Microsoft sign-in can still be done.
  local adv_ip=${PUBLIC_ADDRESS:-auto} adv_port=${PUBLIC_PORT:-${SERVER_PORT:-19132}}
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
    ip: "${adv_ip}"
    port: ${adv_port}
friend-sync:
  update-interval: 60
  auto-follow: true
  auto-unfollow: true
  initial-invite: true
  share-join-code: true
YML
  else
    # Keep the advertised address in sync with the panel variables.
    sed -i -E "s|^(\s*ip:).*|\1 \"${adv_ip}\"|; s|^(\s*port:).*|\1 ${adv_port}|" config.yml
  fi
  cd ..
}

# ---- frp client ------------------------------------------------------------
# FRP_FORWARDS = "proto:localPort:remotePort,..." ; default forwards the server port (TCP+UDP) to PUBLIC_PORT.
frp_forwards() {
  if [ -n "${FRP_FORWARDS}" ]; then printf '%s' "${FRP_FORWARDS}"
  elif [ -n "${PUBLIC_PORT}" ]; then printf 'udp:%s:%s,tcp:%s:%s' "${SERVER_PORT}" "${PUBLIC_PORT}" "${SERVER_PORT}" "${PUBLIC_PORT}"
  fi
}

write_frp_config() {
  local fw item proto lport rport
  fw=$(frp_forwards)
  umask 077
  {
    echo "serverAddr = \"${FRP_SERVER}\""
    echo "serverPort = ${FRP_SERVER_PORT:-7000}"
    echo 'auth.method = "token"'
    echo "auth.token = \"${FRP_TOKEN}\""
    IFS=',' read -ra items <<< "$fw"
    for item in "${items[@]}"; do
      IFS=: read -r proto lport rport <<< "$item"
      [ -n "$proto" ] && [ -n "$lport" ] && [ -n "$rport" ] || continue
      printf '\n[[proxies]]\nname = "bedrock-%s-%s"\ntype = "%s"\nlocalIP = "127.0.0.1"\nlocalPort = %s\nremotePort = %s\n' \
        "$proto" "$rport" "$proto" "$lport" "$rport"
    done
  } > frpc.toml
  umask 022
}

# ---- helpers: tunnel, broadcaster ------------------------------------------
HELPER_PIDS=()
stop_helpers() {
  local p
  for p in "${HELPER_PIDS[@]}"; do kill "$p" 2>/dev/null; wait "$p" 2>/dev/null; done
  HELPER_PIDS=()
}

# Never stops the server: unfinished setup is only reported in the console.
print_setup_status() {
  log "================ セットアップ状況 ================"
  if is_on "$USE_PLAYIT"; then
    if [ -n "${PLAYIT_SECRET}" ]; then
      log "[OK] playit シークレット: 設定済み"
    else
      log "[未完了] playit シークレットが未設定です。playit.gg でエージェントのシークレットキーを発行し、パネルの「playit シークレットキー」に入力して再起動してください"
    fi
  fi
  if is_on "$USE_FRP"; then
    if [ -n "${FRP_SERVER}" ] && [ -n "${FRP_TOKEN}" ] && [ -n "$(frp_forwards)" ]; then
      log "[OK] frp: ${FRP_SERVER}:${FRP_SERVER_PORT:-7000} へ転送します ($(frp_forwards))"
    else
      log "[未完了] frp: 「frp サーバー」「frp トークン」と、公開ポート(または転送の指定)を設定してください"
    fi
  fi
  if [ -n "${PUBLIC_ADDRESS}" ] && [ -n "${PUBLIC_PORT}" ]; then
    log "[OK] 公開アドレス: ${PUBLIC_ADDRESS}:${PUBLIC_PORT}"
  else
    log "[未完了] 公開アドレス/公開ポートが未設定です。トンネル(playit や frp)で外に公開したアドレスとポートを、パネルの「公開アドレス」「公開ポート」に入力して再起動してください(それまでサーバー自体は通常どおり起動します)"
  fi
  if is_on "$USE_BROADCAST"; then
    if [ -d broadcast/cache ] || [ -d broadcast/auth ]; then
      log "[OK] フレンド参加: Microsoft アカウントでサインイン済みの可能性があります"
    else
      log "[未完了] フレンド参加: このあと表示される Microsoft のコードで、ボット用アカウントでサインインしてください"
    fi
  fi
  log "=================================================="
}

start_helpers() {
  if is_on "$USE_PLAYIT"; then
    if [ -x "$PLAYIT_BIN" ]; then
      log "playit を起動します(シークレット未設定の場合、認証URLが表示されることがあります)"
      # playitd needs a writable control-socket path, otherwise it exits with "Failed to bind to socket".
      rm -f "$PLAYIT_SOCK"
      # The daemon takes the key as --secret=<key> (the SECRET_KEY variable is only read by the official Docker entrypoint).
      local args=(--socket-path "$PLAYIT_SOCK" --platform-docker)
      [ -n "${PLAYIT_SECRET}" ] && args+=("--secret=${PLAYIT_SECRET}")
      "$PLAYIT_BIN" "${args[@]}" </dev/null &
      HELPER_PIDS+=($!)
    else
      log "playit が見つかりません(ダウンロードに失敗した可能性があります)。ネットワークの設定を確認してください"
    fi
  fi
  if is_on "$USE_FRP"; then
    if [ ! -x "$FRPC_BIN" ]; then
      log "frpc が見つかりません(ダウンロードに失敗した可能性があります)。ネットワークの設定を確認してください"
    elif [ -z "${FRP_SERVER}" ] || [ -z "${FRP_TOKEN}" ] || [ -z "$(frp_forwards)" ]; then
      log "frp をスキップしました: frp サーバー・トークン・公開ポートを設定してください"
    else
      write_frp_config
      log "frp クライアントを起動します"
      "$FRPC_BIN" -c frpc.toml </dev/null &
      HELPER_PIDS+=($!)
    fi
  fi
  if is_on "$USE_BROADCAST"; then
    if [ -f "$BROADCAST_JAR" ]; then
      write_broadcast_config
      log "MCXboxBroadcast を起動します(初回は下に表示される Microsoft のコードで https://www.microsoft.com/link からサインインしてください)"
      ( cd broadcast && exec java -Xmx256M -jar ../"$BROADCAST_JAR" ) </dev/null &
      HELPER_PIDS+=($!)
    else
      log "MCXboxBroadcast が見つかりません(ダウンロードに失敗した可能性があります)。ネットワークの設定を確認してください"
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
  ensure_transport
  print_setup_status
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
