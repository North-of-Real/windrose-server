# Windrose Dedicated Server — Docker Image

Runs the **Windrose Dedicated Server** (Steam App ID `4129620`) on Linux using
**Wine** (the server is a Windows/Unreal Engine 5 binary).

---

## Quick Start

```bash
# Build the image
docker compose build

# Start the server (first run downloads ~35 GB via SteamCMD)
docker compose up
```

Watch the console for a line like:

```
Invite code: f1014dc1
```

Share that code with friends: **Play → Connect to Server → paste code**.

---

## Configuration

### Via environment variables (docker-compose.yml)

| Variable              | Default              | Description                                         |
|-----------------------|----------------------|-----------------------------------------------------|
| `SERVER_NAME`         | `Windrose Server`    | Display name shown to players                       |
| `INVITE_CODE`         | `changeme`           | ≥6 chars, 0-9 a-z A-Z, case-sensitive               |
| `IS_PASSWORD_PROTECTED` | `false`            | `true` or `false`                                   |
| `SERVER_PASSWORD`     | _(empty)_            | Required if password-protected                      |
| `MAX_PLAYERS`         | `4`                  | Official recommendation: ≤4 for stable performance  |
| `WORLD_ISLAND_ID`     | _(empty)_            | Leave blank on first run; server auto-generates     |

### Via mounted JSON (advanced)

After the first run a `ServerDescription.json` is written to the
`windrose-config` volume. You can edit it directly (stop the server first!),
then restart:

```bash
docker compose down
# edit the file inside the volume or copy one in
docker compose up
```

---

## Volumes

| Volume              | Path in container           | Contents                        |
|---------------------|-----------------------------|---------------------------------|
| `windrose-saves`    | `/data/saves`               | World saves / RocksDB data      |
| `windrose-config`   | `/data/config`              | `ServerDescription.json`, etc.  |
| `windrose-logs`     | `/data/logs`                | Timestamped server logs         |

---

## Networking

Windrose uses **dynamic NAT punch-through** (no fixed ports required for
players to connect via invite code). However the host machine needs:

- **UPnP enabled** on the router, OR
- **`network_mode: host`** in docker-compose (already set by default)

If you need bridge networking instead, uncomment the `ports:` section in
`docker-compose.yml` and update the port numbers once officially documented.

---

## Updating the Server

When the game receives an update, restart the container — SteamCMD runs on
every start and will apply updates automatically before launching:

```bash
docker compose restart
```

Or force a full re-validate:

```bash
docker compose down
docker compose up --build
```

---

## Migrating an Existing World Save

1. Stop the server: `docker compose down`
2. Copy your world folder into the volume:
   ```bash
   docker run --rm -v windrose-saves:/data -v /your/local/save:/src alpine \
     cp -r /src/. /data/SaveProfiles/Default/RocksDB/
   ```
3. Update `WORLD_ISLAND_ID` in `docker-compose.yml` (or in the config JSON)
   to the world folder name (e.g. `EC10598E83A14ED04D9C44CBFBF3F4B1`).
4. Start: `docker compose up`

---

## Known Limitations / TODOs

- **Wine:** The server runs under Wine. Performance is generally fine for
  headless UE5 servers, but expect slightly higher RAM usage than a native binary.
- **Ports:** Official fixed port numbers are not yet documented by the developer.
  The `EXPOSE` lines in the Dockerfile use typical UE5/Steam defaults — update
  if the developer publishes specific ports.
- **No GPU:** GPU drivers are not needed; the dedicated server is headless.
- **SteamCMD anonymous login:** The dedicated server tool is free, so anonymous
  login works. If this ever changes, set `STEAM_LOGIN` env var to your username
  and use a Steam Guard workaround (e.g. cached credentials volume).