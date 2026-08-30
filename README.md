# YT-Downloader v3.0.0

> **Automatic Video Downloader** — Just run it, URLs get downloaded automatically to your host folder.

![Docker](https://img.shields.io/badge/Docker-Alpine-blue?logo=docker)
![yt-dlp](https://img.shields.io/badge/yt--dlp-latest-green)
![License](https://img.shields.io/badge/license-MIT-orange)

---

## Features

- **Auto UID/GID** — Downloaded files are immediately accessible from the host (no permission issues)
- **Dual mode** — Download via argument or queue file
- **Watch mode** — Just write a URL in `data/config/queue.txt`, the container processes it automatically
- **Audio auto-detect** — URLs from SoundCloud/Bandcamp/Spotify are automatically converted to MP3
- **Twitter/X support** — Download videos from Twitter/X at the best quality
- **Auto fallback** — Tries various formats if the primary method fails
- **Duplicate detection** — URLs that have already been downloaded are automatically skipped
- **Local SQLite History** — Download history stored in a local SQLite database
- **3 Database Backends** — SQLite local, direct VPS MySQL/MariaDB, or Cloudflare-tunnel MySQL so multiple PCs share one history (pick via `.env`, nothing hard-coded in compose)
- **Platform Organization** — Downloads are automatically sorted into subfolders by platform (YouTube, Twitter, etc.)
- **Impersonation** — `curl_cffi` support for sites with strict protection
- **Progress bar** — Displayed directly in the terminal during downloads
- **Cookies support** — Export browser cookies to access protected sites
- **Logging** — All activity recorded in `data/logs/`

---

## Usage

### 1. Start the container

```bash
./run.sh
```

### 2a. Direct download

```bash
# YouTube
./run.sh "https://youtube.com/watch?v=..."

# Twitter/X
./run.sh "https://x.com/user/status/2072712422025023645"
./run.sh "https://twitter.com/user/status/2072712422025023645"
```

### 2b. Queue URL (auto-process)

```bash
echo "https://youtube.com/watch?v=..." >> data/config/queue.txt
```

### 2c. Via docker exec

```bash
docker exec yt-downloader ./downloader.sh "https://youtube.com/watch?v=..."
```

---

## Folder Structure

```
yt-downloader/
├── Dockerfile              # Alpine + yt-dlp + ffmpeg + sqlite
├── docker-compose.yml      # Auto UID/GID
├── entrypoint.sh           # Runtime user creation
├── downloader.sh           # Main downloader (watch/argument mode)
├── db_history.sh           # Download history module (SQLite local / MySQL cloud)
├── run.sh                  # One-command launcher
├── .env.example            # DB mode / cloud URI / user template (copy to .env)
├── downloads/
│   ├── Videos/             # Video downloads (organized by platform subfolder)
│   └── Music/              # Audio downloads (organized by platform subfolder)
├── data/
│   ├── config/
│   │   ├── settings.conf   # Format configuration
│   │   ├── queue.txt       # URL queue (write URLs here)
│   │   ├── history.txt     # Old download history (text format)
│   │   ├── history.db      # Download history (SQLite, automatic)
│   │   └── cookies.txt     # Browser cookies (optional)
│   └── logs/               # Automatic logs
├── .gitignore
└── .dockerignore
```

---

## Download History (Local SQLite / Cloud MySQL)

Since v3.0.0, history is stored by the backend selected in `.env`. There are **three modes**:

| Mode | `DB_MODE` | `DB_URI` | Access |
|---|---|---|---|
| **Local** | `local` | ignored | SQLite file `data/config/history.db`, one PC |
| **Cloud — direct VPS IP** | `cloud` | `mysql://user:pass@<VPS_IP>:<PORT>/history` | straight to the VPS over the internet (needs VPS port open) |
| **Cloud — Cloudflare tunnel** | `cloud` | `mysql://user:pass@127.0.0.1:3307/history` | through the bundled `cloudflared-mysql-tcp` container |

> In `local` mode `DB_URI` is ignored. In both `cloud` modes, history is shared across every PC that points to the same server.
> Migration from `history.txt` happens automatically on first run (into whichever backend is active).

### Switch mode — what to change

Edit **only `.env`** and re-run `./run.sh`. No hostnames/credentials are hard-coded in `docker-compose.yml`.

**1 — Local (default):**
```env
DB_MODE=local
```

**2 — Cloud, direct to VPS IP (no tunnel):**
```env
DB_MODE=cloud
DB_URI=mysql://user:secret@103.x.x.x:3307/history
```
- Use the port exposed on the VPS host (here `3307`) and open it in the VPS firewall/security group for your PC's IP.
- No tunnel is used — `run.sh` keeps the tunnel container stopped.

**3 — Cloud, via Cloudflare tunnel:**
```env
DB_MODE=cloud
DB_URI=mysql://user:secret@127.0.0.1:3307/history
CF_TUNNEL_HOSTNAME=db-yt-downloader.example.tld
CF_ACCESS_CLIENT_ID=<Access Client ID>
CF_ACCESS_CLIENT_SECRET=<Access Client Secret>
```
- `run.sh` sees `DB_URI` → `127.0.0.1` and **automatically starts** the `cloudflared-mysql-tcp` container, which opens a `cloudflared access tcp` tunnel on `127.0.0.1:3307`.
- Server-side: published route `db-yt-downloader.example.tld` → **TCP** → `yt-downloader-db:3306` (the port *inside* the docker network), plus an **Access service token** allowed for that hostname.
- Keep MariaDB off the public internet — **no host `ports:` mapping** (`nmap` → `filtered`, never `open`). If you can't edit the firewall, omitting `ports:` and re-creating the container closes exposure entirely.
- The Cloudflare token is shown only once during creation — keep it safe in `.env` (git-ignored).

> Changing only `DB_URI` / `DB_MODE` is enough; the tunnel container lifecycle is managed automatically by `run.sh`.

### Available commands:

```bash
# View last 10 downloads
docker compose exec yt-downloader /app/db_history.sh recent 10

# Download statistics
docker compose exec yt-downloader /app/db_history.sh stats

# Check if a URL has already been downloaded
docker compose exec yt-downloader /app/db_history.sh exists "https://youtube.com/watch?v=..."

# View detailed info for a URL
docker compose exec yt-downloader /app/db_history.sh info "https://youtube.com/watch?v=..."

# Manual migration from history.txt
docker compose exec yt-downloader /app/db_history.sh migrate

# Push local SQLite history into the cloud DB (local → cloud)
docker compose exec yt-downloader /app/db_history.sh migrate-cloud

# Pull the cloud DB into a local SQLite file (cloud → local)
docker compose exec yt-downloader /app/db_history.sh migrate-local [history.db]
```

> **Note:** The `history.db` database is automatically created and migrated from `history.txt` the first time the container runs. No manual setup required.

### Behavior

- Duplicate detection is **global** in `cloud` mode: download on PC 1 → PC 2 skips it (`[SKIP] Already downloaded`).
- Only **history** is shared. Video files stay on the PC that downloaded them (`downloads/` is not synced).

First-run setup with a cloud database (e.g. from a machine that already has local history):

```bash
# 1. Provision a MySQL/MariaDB server.
#    The bundled optional-feature/cloud-database/docker-compose.mariadb.yml
#    runs a persistent MariaDB server (deploy it on your cloud host / VPS):
#      cd optional-feature/cloud-database
#      cp docker-compose.mariadb.env.example .env   # edit credentials
#      docker compose -f docker-compose.mariadb.yml up -d
#    (or use Railway, Aiven, etc. and create a database named e.g. `history`).

# 2. On each PC set DB_MODE=cloud and DB_URI in .env, then push existing
#    local history.db rows into the cloud DB:
docker compose exec yt-downloader /app/db_history.sh migrate-cloud
```

**Reverse migration — cloud back to local SQLite** (e.g. stop using cloud, go back to `DB_MODE=local` on a single PC):

```bash
# 1. Keep DB_MODE=cloud in .env (migrate-local reads the cloud as the source), then:
docker compose exec yt-downloader /app/db_history.sh migrate-local

# 2. It pulls every cloud row into the local history.db (keyed by URL, idempotent —
#    safe to re-run). Without an argument it targets the default local file.

# 3. When done, switch back to local mode:
#    DB_MODE=local   # in .env
docker compose restart yt-downloader
```

> Both `migrate-cloud` and `migrate-local` upsert by unique URL, so they are
> idempotent and safe to re-run. `migrate-local` targets `data/config/history.db`
> by default; pass a different path (inside the container) to restore a copy instead.


> Full step-by-step deployment guide (server setup, firewall, PC `.env`,
> migration, backup, security checklist): see
> [`optional-feature/cloud-database/README.md`](optional-feature/cloud-database/README.md).

---

## Configuration

Edit `data/config/settings.conf`:

```ini
DEFAULT_FORMAT="bv*+ba/best"     # Best video format
AUDIO_FORMAT="ba/bestaudio"      # Best audio format
```

### Database backend (`.env`)

The database is chosen entirely from `data/../.env` at the project root — see
[Download History](#download-history-local-sqlite--cloud-mysql) for the 3 modes,
the exact variables, and what to change on each PC. Key variables:

| Variable | Purpose |
|---|---|
| `DB_MODE` | `local` (SQLite) \| `cloud` (MySQL/MariaDB) |
| `DB_URI` | MySQL connection string; `127.0.0.1` = tunnel mode |
| `CF_TUNNEL_HOSTNAME` | Cloudflare tunnel hostname (tunnel mode only) |
| `CF_ACCESS_CLIENT_ID` / `CF_ACCESS_CLIENT_SECRET` | Cloudflare Access service token (tunnel mode only) |

---

## Twitter/X — Important Notes

Twitter/X **requires cookies** from a logged-in account. Even public videos often cannot be downloaded without cookies due to Twitter's restrictions.

**Steps:**
1. Open Twitter/X.com in your browser
2. Log in to your Twitter account (a free account is sufficient)
3. Export cookies to `data/config/cookies.txt` (see cookies guide below)
4. Download Twitter/X URLs as usual

```bash
./run.sh "https://x.com/i/status/2072712422025023645"
```

> **Tip:** If you get an error saying "Twitter requires logging in", your cookies have expired. Re-export cookies from your browser.

---

## Cookies — Accessing Protected Sites

Some sites with Cloudflare protection or authentication requirements (like Twitter/X) need **browser cookies** to be downloadable.

### Method 1: Export cookies.txt (recommended)

1. Install a browser extension:
   - **Chrome/Edge**: [Get cookies.txt LOCALLY](https://chrome.google.com/webstore/detail/get-cookiestxt-locally/cclelndahbckbenkjhflpdbgdldlbecc)
   - **Firefox**: [cookies.txt](https://addons.mozilla.org/en-US/firefox/addon/cookies-txt/)

2. Open the target site, log in, then export cookies → save as `data/config/cookies.txt`

3. Done! The container will automatically use those cookies.

### Method 2: Extract via command line (Python)

```bash
# Install browsercookie
pip install browsercookie

# Extract cookies from browser (Chrome/Edge/Firefox)
python3 -c "
import browsercookie, http.cookiejar
cj = browsercookie.chrome()  # change .chrome() to .firefox() if using Firefox
with open('data/config/cookies.txt', 'w') as f:
    for c in cj:
        f.write(f'{c.domain}\tTRUE\t{c.path}\tFALSE\t{int(c.expires if c.expires else 0)}\t{c.name}\t{c.value}\n')
print('Cookies saved to data/config/cookies.txt')
"
```

> **Note:** `data/config/cookies.txt` is git-ignored (via `.gitignore`).

---

## F.A.Q.

**Q: How do I switch the database mode?**
Edit only `.env`, then run `./run.sh`. See [Download History](#download-history-local-sqlite--cloud-mysql) for the three modes and their `.env` examples. Use `./run.sh` (not bare `docker compose up`) — it manages the tunnel container for you.

**Q: How do I connect to a Cloud DB without opening it to the public internet?**
Use tunnel mode — `DB_URI=mysql://user:pass@127.0.0.1:3307/...` plus the `CF_*` variables. `run.sh` auto-starts `cloudflared-mysql-tcp`, which dials the tunneled hostname and exposes a local `127.0.0.1:3307`. The DB port never needs to be exposed.

**Q: I get `502` / `websocket: bad handshake` when using tunnel mode.**
That's a Cloudflare side / origin issue, not the app: the edge cannot reach your DB. Check on the VPS: (1) the tunnel container is running and healthy, (2) the MariaDB container is on the same docker network as the tunnel, (3) the published route is `TCP → <db-container>:3306` (the port *inside* the network, not the host-published one).

**Q: My Cloudflare Access token is only shown once. What if I lose it?**
Create a new service token in Zero Trust (Access → Service Auth → Service Tokens), add it to the Access application policy for the hostname, and update `CF_ACCESS_CLIENT_ID` / `CF_ACCESS_CLIENT_SECRET` in `.env`. Then `./run.sh`.

**Q: Downloads fail with "SSL: handshake timed out" / no internet from the container.**
Usually the Docker bridge has no working egress (common on WSL2 mirrored networking) while the host itself works. The images run with `network_mode: host`, so they share the host's network — verify the host can reach the site (`curl -I https://www.youtube.com`). If you're on native Linux Docker, host networking also works unchanged.

**Q: The queue isn't processing.**
`data/config/queue.txt` is watched by `inotifywait` inside the running container. Make sure the container is up (`docker ps`), add one URL per line, and the file is closed/saved (`>>` or save). Check logs in `data/logs/`.

**Q: A URL is skipped even though I want to re-download it.**
Duplicate protection by URL is intentional — it works globally in cloud mode (downloaded on PC 1 → skipped on PC 2). It only guards history; see `docker compose exec yt-downloader /app/db_history.sh` to inspect/manage entries.

**Q: No `cloudflared` / something installed on my host?**
Nothing. Everything (the app and the tunnel) is a Docker container. The only host requirement is the Docker Engine itself.

---

## Notes

- Container runs in the background (`restart: unless-stopped`)
- Downloaded files are automatically git-ignored
- Download history is stored in SQLite locally, or in a shared MySQL/MariaDB server (see [Download History](#download-history-local-sqlite--cloud-mysql)) — set via `DB_MODE` in `.env`
- URLs that have already been downloaded are automatically skipped (duplicate check)


---

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for the full history of changes.

---

## Credits

**Created by [gylangsatria](https://github.com/gylangsatria)**

Powered by:
- [yt-dlp](https://github.com/yt-dlp/yt-dlp)
- [ffmpeg](https://ffmpeg.org/)
- [Alpine Linux](https://alpinelinux.org/)
- [SQLite](https://www.sqlite.org/)
- [MariaDB](https://mariadb.org/)
