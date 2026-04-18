# ============================================================
# Windrose Dedicated Server — Docker Image
# Runs WindroseServer.exe (Windows/UE5) under Wine on Linux
# Steam App ID: 4129620
# ============================================================

FROM steamcmd/steamcmd:ubuntu-24

# ── Labels ────────────────────────────────────────────────
LABEL maintainer="ryan@northofreal.com"
LABEL description="Windrose Dedicated Server (Wine + SteamCMD)"
LABEL steam.appid="4129620"

# ── Environment ───────────────────────────────────────────
ENV DEBIAN_FRONTEND=noninteractive \
    WINEDEBUG=-all \
    WINEPREFIX=/opt/windrose-wine \
    WINEARCH=win64 \
    STEAM_APP_ID=4129620 \
    SERVER_DIR=/opt/windrose-server \
    DATA_DIR=/data \
    # Server config defaults (override via env or volume-mounted JSON)
    SERVER_NAME="Windrose Server" \
    INVITE_CODE="changeme" \
    IS_PASSWORD_PROTECTED="false" \
    SERVER_PASSWORD="" \
    MAX_PLAYERS=4

# ── Add 32-bit arch and Wine repo ─────────────────────────
RUN dpkg --add-architecture i386 && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
    wget \
    gnupg2 \
    software-properties-common \
    ca-certificates && \
    # Wine HQ repo for a recent stable Wine
    mkdir -pm755 /etc/apt/keyrings && \
    wget -O /etc/apt/keyrings/winehq-archive.key \
    https://dl.winehq.org/wine-builds/winehq.key && \
    wget -NP /etc/apt/sources.list.d/ \
    https://dl.winehq.org/wine-builds/ubuntu/dists/noble/winehq-noble.sources && \
    apt-get update && \
    apt-get install -y --install-recommends winehq-stable && \
    # Winetricks for VC++ runtime
    wget -O /usr/local/bin/winetricks \
    https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks && \
    chmod +x /usr/local/bin/winetricks && \
    apt-get install -y --no-install-recommends \
    cabextract \
    unzip \
    jq \
    procps && \
    rm -rf /var/lib/apt/lists/*

# ── Create directories ────────────────────────────────────
RUN mkdir -p "${SERVER_DIR}" "${DATA_DIR}" "${WINEPREFIX}"

# ── Initialise Wine prefix and install VC++ runtimes ─────
# Done at build time so first-start is fast.
# Uses Xvfb-less approach — UE5 server is truly headless.
RUN wineboot --init && \
    winetricks -q vcrun2019 && \
    wineserver --wait

# ── Copy helper scripts ───────────────────────────────────
COPY scripts/ /scripts/
RUN chmod +x /scripts/*.sh

# ── Persistent data volume ────────────────────────────────
# Mounts: saves, config JSONs, logs
VOLUME ["${DATA_DIR}"]

# ── Ports ─────────────────────────────────────────────────
# Windrose uses dynamic NAT punch-through, but these are the
# typical Unreal Engine / Steam ports to expose on the host.
# No fixed game port is documented yet — update as needed.
EXPOSE 7777/udp   
EXPOSE 27015/udp  
EXPOSE 27016/tcp  

# ── Entrypoint ────────────────────────────────────────────
ENTRYPOINT ["/scripts/entrypoint.sh"]