#!/usr/bin/env bash
set -euo pipefail

# ── Colour helpers ────────────────────────────────────────
INFO()  { echo -e "\e[36m[INFO]\e[0m  $*"; }
WARN()  { echo -e "\e[33m[WARN]\e[0m  $*"; }
ERROR() { echo -e "\e[31m[ERROR]\e[0m $*" >&2; }

SERVER_DIR="${SERVER_DIR:-/opt/windrose-server}"
DATA_DIR="${DATA_DIR:-/data}"
SAVES_DIR="${DATA_DIR}/saves"
CONFIG_DIR="${DATA_DIR}/config"
LOG_DIR="${DATA_DIR}/logs"
STEAM_APP_ID="${STEAM_APP_ID:-4129620}"
STEAM_LOGIN="${STEAM_LOGIN:-anonymous}"

mkdir -p "${SAVES_DIR}" "${CONFIG_DIR}" "${LOG_DIR}"

# ── Step 1: Download / Update server files via SteamCMD ──
INFO "Running SteamCMD to install/update Windrose Dedicated Server (AppID ${STEAM_APP_ID})..."
steamcmd \
    +@sSteamCmdForcePlatformType windows \
    +force_install_dir "${SERVER_DIR}" \
    +login "${STEAM_LOGIN}" \
    +app_update "${STEAM_APP_ID}" validate \
    +quit

INFO "SteamCMD finished."

# ── Step 2: Locate the server executable ─────────────────
# UE5 dedicated servers typically live in:
#   <root>/WindroseServer/Binaries/Win64/WindroseServer.exe
#   OR the root StartServerForeground.bat points to one of these.
SERVER_EXE=$(find "${SERVER_DIR}" -iname "WindroseServer.exe" | head -1 || true)

if [[ -z "${SERVER_EXE}" ]]; then
    ERROR "WindroseServer.exe not found under ${SERVER_DIR}."
    ERROR "Directory listing:"
    find "${SERVER_DIR}" -maxdepth 4 | head -60
    exit 1
fi

INFO "Found server executable: ${SERVER_EXE}"
SERVER_ROOT=$(dirname "$(dirname "$(dirname "$(dirname "${SERVER_EXE}")")")")
INFO "Server root: ${SERVER_ROOT}"

# ── Step 3: Symlink save data to persistent volume ────────
# Server stores saves in: <root>/R5/Saved/
INTERNAL_SAVED="${SERVER_ROOT}/R5/Saved"
mkdir -p "${INTERNAL_SAVED}"

# If saves dir is empty first run, seed it from the server default (if any)
if [[ -d "${INTERNAL_SAVED}" && "$(ls -A "${INTERNAL_SAVED}" 2>/dev/null)" ]]; then
    INFO "Seeding persistent saves from server defaults..."
    cp -rn "${INTERNAL_SAVED}/." "${SAVES_DIR}/" 2>/dev/null || true
fi

# Replace internal Saved with symlink to persistent volume
rm -rf "${INTERNAL_SAVED}"
ln -sfn "${SAVES_DIR}" "${INTERNAL_SAVED}"
INFO "Saves symlinked: ${INTERNAL_SAVED} → ${SAVES_DIR}"

# ── Step 4: Write / merge ServerDescription.json ──────────
ROOT_CONFIG="${SERVER_ROOT}/ServerDescription.json"
PERSISTENT_CONFIG="${CONFIG_DIR}/ServerDescription.json"

if [[ ! -f "${PERSISTENT_CONFIG}" ]]; then
    INFO "No persistent ServerDescription.json found — generating from environment..."
    /scripts/write-config.sh "${PERSISTENT_CONFIG}"
else
    INFO "Using existing persistent ServerDescription.json from ${PERSISTENT_CONFIG}"
fi

# Always copy config into server root so server sees it
cp "${PERSISTENT_CONFIG}" "${ROOT_CONFIG}"

# ── Step 5: Launch under Wine ─────────────────────────────
LOG_FILE="${LOG_DIR}/windrose-$(date +%Y%m%d-%H%M%S).log"

INFO "Launching WindroseServer.exe under Wine..."
INFO "Logs → ${LOG_FILE}"
INFO "----------------------------------------------"

# UE5 server args: -log keeps console output, -nosteam disables client Steam UI
exec wine "${SERVER_EXE}" \
    -log \
    -nosteam \
    2>&1 | tee "${LOG_FILE}"