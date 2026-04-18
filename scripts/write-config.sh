#!/usr/bin/env bash
# write-config.sh <output-path>
# Writes ServerDescription.json from environment variables.
set -euo pipefail

OUTPUT="${1:-/data/config/ServerDescription.json}"

cat > "${OUTPUT}" <<EOF
{
  "PersistentServerId": "",
  "InviteCode": "${INVITE_CODE:-changeme}",
  "IsPasswordProtected": ${IS_PASSWORD_PROTECTED:-false},
  "Password": "${SERVER_PASSWORD:-}",
  "ServerName": "${SERVER_NAME:-Windrose Server}",
  "WorldIslandId": "${WORLD_ISLAND_ID:-}",
  "MaxPlayerCount": ${MAX_PLAYERS:-4},
  "P2pProxyAddress": ""
}
EOF

echo "[INFO]  Wrote ServerDescription.json to ${OUTPUT}"
cat "${OUTPUT}"