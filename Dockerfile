# BUILD THE SERVER IMAGE
FROM --platform=linux/amd64 debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN dpkg --add-architecture i386 && \
    apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    gnupg \
    unzip \
    procps \
    libicu-dev \
    gettext-base \
    xvfb \
    xauth \
    jq \
    && curl -fsSL https://dl.winehq.org/wine-builds/winehq.key | \
    gpg --dearmor -o /usr/share/keyrings/winehq-archive.key \
    && echo "deb [arch=amd64,i386 signed-by=/usr/share/keyrings/winehq-archive.key] https://dl.winehq.org/wine-builds/debian/ bookworm main" \
    > /etc/apt/sources.list.d/winehq.list \
    && apt-get update \
    && apt-get install -y --install-recommends winehq-stable \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install .NET 8 runtime (required for DepotDownloader)
RUN curl -sL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh && \
    chmod +x /tmp/dotnet-install.sh && \
    /tmp/dotnet-install.sh --channel 8.0 --runtime dotnet --install-dir /usr/share/dotnet && \
    ln -s /usr/share/dotnet/dotnet /usr/bin/dotnet && \
    rm /tmp/dotnet-install.sh

# Download DepotDownloader
ARG DEPOT_DOWNLOADER_VERSION=3.4.0
RUN curl -sL \
    "https://github.com/SteamRE/DepotDownloader/releases/download/DepotDownloader_${DEPOT_DOWNLOADER_VERSION}/DepotDownloader-linux-x64.zip" -o \
    /tmp/dd.zip && \
    mkdir -p /depotdownloader && \
    unzip /tmp/dd.zip -d /depotdownloader && \
    chmod +x /depotdownloader/DepotDownloader && \
    rm /tmp/dd.zip

RUN useradd -m -s /bin/bash steam

# Init Wine prefix
ENV WINEPREFIX=/home/steam/.wine \
    WINEARCH=win64 \
    WINEDLLOVERRIDES="mscoree,mshtml=" \
    DISPLAY=:0
RUN Xvfb :0 -screen 0 1024x768x16 & \
    sleep 2 && \
    su -l steam -c "WINEPREFIX=/home/steam/.wine WINEARCH=win64 WINEDLLOVERRIDES='mscoree,mshtml=' winecfg -v win10 >/dev/null 2>&1; wineboot --init >/dev/null 2>&1" && \
    kill %1 2>/dev/null; true

ENV HOME=/home/steam \
    UPDATE_ON_START=true

COPY ./scripts /home/steam/server/
COPY branding /branding

RUN mkdir -p /home/steam/server-files && \
    chmod +x /home/steam/server/*.sh

WORKDIR /home/steam/server

HEALTHCHECK --start-period=5m \
    CMD pgrep "wine" > /dev/null || exit 1

ENTRYPOINT ["/home/steam/server/init.sh"]