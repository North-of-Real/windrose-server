#!/usr/bin/env bash
set -euo pipefail

# ── Colour helpers ────────────────────────────────────────
INFO()  { echo -e "\e[36m[INFO]\e[0m  $*"; }
WARN()  { echo -e "\e[33m[WARN]\e[0m  $*"; }
ERROR() { echo -e "\e[31m[ERROR]\e[0m $*" >&2; }

# ── Paths ─────────────────────────────────────────────────
SERVER_DIR="${SERVER_DIR:-/opt/windrose-server}"
DATA_DIR="${DATA_DIR:-/data}"
SAVES_DIR="${DATA_DIR}/saves"
CONFIG_DIR="${DATA_DIR}/config"
LOG_DIR="${DATA_DIR}/logs"
STEAM_APP_ID="${STEAM_APP_ID:-4129620}"
STEAM_LOGIN="${STEAM_LOGIN:-anonymous}"

mkdir -p "${SAVES_DIR}" "${CONFIG_DIR}" "${LOG_DIR}"

# ── Step 1: Initialise Wine prefix (runtime, not build time) ──
# wineboot needs HOME, USER, and a writable environment — all
# available here at container start but not during docker build.
if [[ ! -f "${WINEPREFIX}/system.reg" ]]; then
    INFO "Initialising Wine prefix at ${WINEPREFIX} ..."
    export HOME="${HOME:-/root}"
    wineboot --init 2>&1 | grep -v "^wine:" || true
    wineserver --wait
    INFO "Wine prefix ready."
else
    INFO "Wine prefix already initialised, skipping."
fi

# ── Step 2: Download / Update server files via SteamCMD ──
INFO "Running SteamCMD to install/update Windrose Dedicated Server (AppID ${STEAM_APP_ID})..."
steamcmd \
    +@sSteamCmdForcePlatformType windows \
    +force_install_dir "${SERVER_DIR}" \
    +login "${STEAM_LOGIN}" \
    +app_update "${STEAM_APP_ID}" validate \
    +quit

INFO "SteamCMD finished."

# ── Step 3: Locate the server executable ─────────────────
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

# ── Step 4: Symlink save data to persistent volume ────────
INTERNAL_SAVED="${SERVER_ROOT}/R5/Saved"
mkdir -p "${INTERNAL_SAVED}"

if [[ "$(ls -A "${INTERNAL_SAVED}" 2>/dev/null)" ]]; then
    INFO "Seeding persistent saves from server defaults..."
    cp -rn "${INTERNAL_SAVED}/." "${SAVES_DIR}/" 2>/dev/null || true
fi

rm -rf "${INTERNAL_SAVED}"
ln -sfn "${SAVES_DIR}" "${INTERNAL_SAVED}"
INFO "Saves symlinked: ${INTERNAL_SAVED} → ${SAVES_DIR}"

# ── Step 5: Write / merge ServerDescription.json ──────────
ROOT_CONFIG="${SERVER_ROOT}/ServerDescription.json"
PERSISTENT_CONFIG="${CONFIG_DIR}/ServerDescription.json"

if [[ ! -f "${PERSISTENT_CONFIG}" ]]; then
    INFO "No persistent ServerDescription.json found — generating from environment..."
    /scripts/write-config.sh "${PERSISTENT_CONFIG}"
else
    INFO "Using existing persistent ServerDescription.json from ${PERSISTENT_CONFIG}"
fi

cp "${PERSISTENT_CONFIG}" "${ROOT_CONFIG}"

# ── Step 6: Launch under Wine ─────────────────────────────
LOG_FILE="${LOG_DIR}/windrose-$(date +%Y%m%d-%H%M%S).log"

INFO "Launching WindroseServer.exe under Wine..."
INFO "Logs → ${LOG_FILE}"
INFO "----------------------------------------------"

exec wine "${SERVER_EXE}" \
    -log \
    -nosteam \
    2>&1 | tee "${LOG_FILE}"