#!/bin/bash
# Standard Pterodactyl entrypoint: expand {{VAR}} in STARTUP and run it.
cd /home/container || exit 1

export INTERNAL_IP=$(ip route get 1 2>/dev/null | awk '{print $(NF-2);exit}')

PARSED=$(echo "${STARTUP}" | sed -e 's/{{/${/g' -e 's/}}/}/g' | eval echo "$(cat -)")
printf '\033[1m\033[33mcontainer@pterodactyl~ \033[0m%s\n' "$PARSED"
exec env ${PARSED}
