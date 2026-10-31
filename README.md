# broadcast-BE-egg

Pterodactyl egg for a Minecraft **Bedrock Edition (統合版)** server that

- needs **no port forwarding** – a [playit.gg](https://playit.gg) UDP tunnel runs inside the same container
- shows up in the **Xbox friends list** – [MCXboxBroadcast](https://github.com/MiniDigger/MCXboxBroadcast) (standalone) advertises the tunnel address

## Setup

1. The `Build image` workflow publishes `ghcr.io/<owner>/broadcast-be-egg:latest` (make the package public).
   If your owner is not `shishen575`, edit `docker_images` in the egg JSON.
2. Import `egg-bedrock-tunnel-broadcast.json` in the Pterodactyl admin panel and create a server.
   The panel allocation can be any local port; it is only used inside the container.
3. Start the server. In the console:
   - **playit**: open the printed claim URL, then in the playit dashboard create a
     **Minecraft Bedrock (UDP)** tunnel pointing to `127.0.0.1` and the server's port.
   - Copy the tunnel's public host/port into the `PUBLIC_ADDRESS` / `PUBLIC_PORT` variables and restart.
   - **Broadcast**: sign in with the printed Microsoft code (https://microsoft.com/link) using a
     *separate Xbox account* for the bot. Friends add that account and join from their friends list.
4. Players can also join directly with the tunnel address from "Add Server".

## Auto update

With `AUTO_UPDATE=1` (default) the server checks every `UPDATE_INTERVAL` minutes (default 60) for new versions of
Bedrock Dedicated Server, playit and MCXboxBroadcast. When one is found it announces in-game with `say`
(`UPDATE_WARNING` minutes, default 5, plus 1 minute and 10 second reminders), stops the server and restarts it;
the new versions are downloaded on that restart. Notes:

- BDS is not touched when `BEDROCK_VERSION` is pinned to a specific version.
- Before a BDS update `worlds/` is backed up to `backups/` (the latest 3 are kept). `server.properties`, `allowlist.json` and `permissions.json` are never overwritten.
- Installed versions are recorded in `.versions/`.
- Update is a full restart of the container's processes, so players are disconnected briefly.

## Notes

- `BROADCAST_VERSION` / `BROADCAST_PROTOCOL` are only written to `broadcast/config.yml` on first start; after a BDS update edit them there if friends see a version mismatch.
- Config for the broadcaster lives in `broadcast/config.yml` (the advertised ip/port are re-synced from the variables on each start).
- `USE_PLAYIT=0` / `USE_BROADCAST=0` disable either part.
- Not yet tested against live services: playit CLI flags (`--secret`) and the MCXboxBroadcast config keys follow upstream docs and may need adjusting.
