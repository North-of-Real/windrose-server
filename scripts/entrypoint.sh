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

# ── Fix: XDG_RUNTIME_DIR required by Wine ─────────────────
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/runtime-root}"
mkdir -p "${XDG_RUNTIME_DIR}"
chmod 700 "${XDG_RUNTIME_DIR}"

# ── Step 1: Start Xvfb (virtual display) ─────────────────
# WindroseServer.exe attempts to create windows even as a dedicated
# server, so Wine needs a display. Xvfb provides a fake one.
DISPLAY="${DISPLAY:-:0}"
export DISPLAY

INFO "Starting Xvfb on display ${DISPLAY} ..."
Xvfb "${DISPLAY}" -screen 0 1024x768x16 &
XVFB_PID=$!
# Give Xvfb a moment to be ready
sleep 2
INFO "Xvfb started (PID ${XVFB_PID})."

# ── Step 2: Initialise Wine prefix ────────────────────────
if [[ ! -f "${WINEPREFIX}/system.reg" ]]; then
    INFO "Initialising Wine prefix at ${WINEPREFIX} ..."
    export HOME="${HOME:-/root}"
    wineboot --init 2>&1 | grep -v "^wine:" || true
    wineserver --wait
    INFO "Wine prefix ready."
else
    INFO "Wine prefix already initialised, skipping."
fi

# ── Step 3: Download / Update server files via SteamCMD ──
INFO "Running SteamCMD to install/update Windrose Dedicated Server (AppID ${STEAM_APP_ID})..."
steamcmd \
    +@sSteamCmdForcePlatformType windows \
    +force_install_dir "${SERVER_DIR}" \
    +login "${STEAM_LOGIN}" \
    +app_update "${STEAM_APP_ID}" validate \
    +quit

INFO "SteamCMD finished."

# ── Step 4: Locate the server executable ─────────────────
SERVER_EXE=$(find "${SERVER_DIR}" -iname "WindroseServer.exe" | head -1 || true)

if [[ -z "${SERVER_EXE}" ]]; then
    ERROR "WindroseServer.exe not found under ${SERVER_DIR}."
    ERROR "Directory listing:"
    find "${SERVER_DIR}" -maxdepth 4 | head -60
    exit 1
fi

INFO "Found server executable: ${SERVER_EXE}"
SERVER_ROOT="${SERVER_DIR}"
INFO "Server root: ${SERVER_ROOT}"

# ── Step 5: Symlink save data to persistent volume ────────
INTERNAL_SAVED="${SERVER_ROOT}/R5/Saved"
mkdir -p "$(dirname "${INTERNAL_SAVED}")"

if [[ -d "${INTERNAL_SAVED}" && "$(ls -A "${INTERNAL_SAVED}" 2>/dev/null)" && \
      -z "$(ls -A "${SAVES_DIR}" 2>/dev/null)" ]]; then
    INFO "Seeding persistent saves from server defaults..."
    cp -rn "${INTERNAL_SAVED}/." "${SAVES_DIR}/" 2>/dev/null || true
fi

rm -rf "${INTERNAL_SAVED}"
ln -sfn "${SAVES_DIR}" "${INTERNAL_SAVED}"
INFO "Saves symlinked: ${INTERNAL_SAVED} → ${SAVES_DIR}"

# ── Step 6: Write / merge ServerDescription.json ──────────
ROOT_CONFIG="${SERVER_ROOT}/ServerDescription.json"
PERSISTENT_CONFIG="${CONFIG_DIR}/ServerDescription.json"

if [[ ! -f "${PERSISTENT_CONFIG}" ]]; then
    INFO "No persistent ServerDescription.json found — generating from environment..."
    /scripts/write-config.sh "${PERSISTENT_CONFIG}"
else
    INFO "Using existing persistent ServerDescription.json from ${PERSISTENT_CONFIG}"
fi

cp "${PERSISTENT_CONFIG}" "${ROOT_CONFIG}"

# ── Step 7: Launch under Wine via Xvfb ───────────────────
LOG_FILE="${LOG_DIR}/windrose-$(date +%Y%m%d-%H%M%S).log"

INFO "Launching WindroseServer.exe under Wine..."
INFO "Logs → ${LOG_FILE}"
INFO "----------------------------------------------"

# Capture stdout and stderr separately so neither is swallowed.
wine "${SERVER_EXE}" \
    -port "${SERVER_PORT:-7777}" \
    -log \
    -nosteam \
    > >(tee "${LOG_FILE}") \
    2> >(tee "${LOG_FILE}.stderr" >&2)

EXIT_CODE=$?
INFO "Wine exited with code ${EXIT_CODE}"

if [[ -s "${LOG_FILE}.stderr" ]]; then
    INFO "--- stderr ---"
    cat "${LOG_FILE}.stderr"
fi

# Clean up Xvfb
kill "${XVFB_PID}" 2>/dev/null || true

exit ${EXIT_CODE}