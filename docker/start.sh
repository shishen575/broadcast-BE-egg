#!/bin/bash
# Runs inside the Pterodactyl container: playit tunnel + MCXboxBroadcast + BDS.
cd /home/container || exit 1

PLAYIT_BIN=./playit
BROADCAST_JAR=./MCXboxBroadcastStandalone.jar
ARCH=$(uname -m)

log() { printf '[egg] %s\n' "$*"; }

fetch_playit() {
  [ -x "$PLAYIT_BIN" ] && return
  local asset=playit-linux-amd64
  [ "$ARCH" = aarch64 ] && asset=playit-linux-aarch64
  log "Downloading playit agent ($asset)"
  curl -fsSL -o "$PLAYIT_BIN" "https://github.com/playit-cloud/playit-agent/releases/latest/download/$asset" \
    && chmod +x "$PLAYIT_BIN"
}

fetch_broadcast() {
  [ -f "$BROADCAST_JAR" ] && return
  log "Downloading MCXboxBroadcast standalone"
  curl -fsSL -o "$BROADCAST_JAR" \
    "https://github.com/MiniDigger/MCXboxBroadcast/releases/latest/download/MCXboxBroadcastStandalone.jar"
}

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

PIDS=()
cleanup() { for p in "${PIDS[@]}"; do kill "$p" 2>/dev/null; done; }
trap cleanup EXIT

if [ "${USE_PLAYIT}" = "1" ]; then
  fetch_playit
  PLAYIT_ARGS=()
  [ -n "${PLAYIT_SECRET}" ] && PLAYIT_ARGS+=(--secret "${PLAYIT_SECRET}")
  log "Starting playit tunnel (open the claim URL below on first run)"
  "$PLAYIT_BIN" "${PLAYIT_ARGS[@]}" </dev/null &
  PIDS+=($!)
fi

if [ "${USE_BROADCAST}" = "1" ]; then
  if [ -z "${PUBLIC_ADDRESS}" ] || [ -z "${PUBLIC_PORT}" ]; then
    log "Broadcast skipped: set PUBLIC_ADDRESS and PUBLIC_PORT (tunnel address from the playit dashboard)"
  else
    fetch_broadcast
    write_broadcast_config
    log "Starting MCXboxBroadcast (sign in with the Microsoft code below on first run)"
    (cd broadcast && java -Xmx256M -jar ../"$BROADCAST_JAR") </dev/null &
    PIDS+=($!)
  fi
fi

# BDS stays in the foreground so the panel console can write to its stdin.
export LD_LIBRARY_PATH=.
./bedrock_server
