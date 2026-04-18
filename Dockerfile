# ============================================================
# Windrose Dedicated Server — Docker Image
# Runs WindroseServer.exe (Windows/UE5) under Wine on Linux
# Steam App ID: 4129620
# ============================================================

FROM steamcmd/steamcmd:ubuntu-24

# ── Labels ────────────────────────────────────────────────
LABEL maintainer="Ryan Singleton"
LABEL description="Windrose Dedicated Server (Wine + SteamCMD)"
LABEL steam.appid="4129620"

# ── Environment ───────────────────────────────────────────
# Only non-sensitive, non-secret values here.
# Pass SERVER_NAME, INVITE_CODE, IS_PASSWORD_PROTECTED,
# SERVER_PASSWORD, MAX_PLAYERS at runtime via docker-compose
# environment: block or -e flags — never bake secrets into the image.
ENV DEBIAN_FRONTEND=noninteractive \
    WINEDEBUG=-all \
    WINEPREFIX=/opt/windrose-wine \
    WINEARCH=win64 \
    STEAM_APP_ID=4129620 \
    SERVER_DIR=/opt/windrose-server \
    DATA_DIR=/data

# ── Add 32-bit arch and Wine repo ─────────────────────────
RUN dpkg --add-architecture i386 && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
    wget \
    gnupg2 \
    software-properties-common \
    ca-certificates && \
    mkdir -pm755 /etc/apt/keyrings && \
    wget -O /etc/apt/keyrings/winehq-archive.key \
    https://dl.winehq.org/wine-builds/winehq.key && \
    wget -NP /etc/apt/sources.list.d/ \
    https://dl.winehq.org/wine-builds/ubuntu/dists/noble/winehq-noble.sources && \
    apt-get update && \
    apt-get install -y --install-recommends winehq-stable && \
    apt-get install -y --no-install-recommends \
    jq \
    procps && \
    rm -rf /var/lib/apt/lists/*

# ── Create directories ────────────────────────────────────
RUN mkdir -p "${SERVER_DIR}" "${DATA_DIR}" "${WINEPREFIX}"

# NOTE: Wine prefix initialisation (wineboot --init) is intentionally
# deferred to the entrypoint script. Running wineboot at build time
# fails inside buildkit because it requires a writable home directory,
# a proper USER environment, and optionally a display — none of which
# are guaranteed during docker build. UE5 dedicated servers also ship
# their own VC++ redistributables, so winetricks is not needed.

# ── Copy helper scripts ───────────────────────────────────
COPY scripts/ /scripts/
RUN chmod +x /scripts/*.sh

# ── Persistent data volume ────────────────────────────────
VOLUME ["${DATA_DIR}"]

# ── Ports ─────────────────────────────────────────────────
# Windrose uses dynamic NAT punch-through; expose standard UE5/Steam
# ports as a baseline — update once official ports are documented.
EXPOSE 7777/udp
EXPOSE 27015/udp
EXPOSE 27016/tcp

# ── Entrypoint ────────────────────────────────────────────
ENTRYPOINT ["/scripts/entrypoint.sh"]