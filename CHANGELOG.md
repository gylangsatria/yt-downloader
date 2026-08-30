# Changelog

## v3.1.0 (2026-08-30)
### Added
- **Three database backends, chosen from `.env`** — Local SQLite, Cloud MySQL via direct VPS IP, or Cloud MySQL via Cloudflare tunnel. Switching only needs the correct `DB_URI`/`DB_MODE`.
- **Cloudflare tunnel support** — bundled `cloudflared-mysql-tcp` container opens a `cloudflared access tcp` tunnel on `127.0.0.1:3307`, so a cloud DB stays reachable without exposing its 3306 port to the internet. No binary installed on the host.
- **`CF_TUNNEL_HOSTNAME` / `CF_ACCESS_CLIENT_ID` / `CF_ACCESS_CLIENT_SECRET`** — `.env` variables for tunnel mode.
- **F.A.Q.** — troubleshooting section added to `README.md`.

### Changed
- `docker-compose.yml` — **no hard-coded hostnames/IPs**; all DB connection values come from `.env` via interpolation (`${DB_URI}`, `${CF_TUNNEL_HOSTNAME}`, etc.).
- `yt-downloader` uses `network_mode: host` so yt-dlp reaches download sources when the Docker bridge has no working egress (e.g. WSL2 mirrored networking).
- `cloudflared-mysql-tcp` also uses `network_mode: host` so it binds `127.0.0.1:3307` directly, bypassing `docker-proxy` loopback (unreliable in WSL). On native Linux Docker, `host` networking is fully supported and the exact same compose file runs as-is.
- `run.sh` — auto-starts the tunnel container when `DB_URI` points to `127.0.0.1`, and stops it otherwise. Entry point is `./run.sh` (not bare `docker compose up`).
- `README.md` / `.env.example` — documented all three modes with per-mode `.env` examples.

### Notes
- Tunnel mode server-side requires a published Cloudflare route `TCP → <db-container>:3306` (the port *inside* the docker network) plus an Access service token allowed for that hostname.

## v3.0.0 (2026-08-30)
### Added
- **Shared (Cloud) Database** — history can now be stored on a remote **MySQL/MariaDB** server instead of local SQLite, so multiple PCs running this app share the same download history.
- **Backend selection via `.env`** — `DB_MODE=local` (SQLite, default) or `DB_MODE=cloud` (MySQL/MariaDB). All credentials and the cloud link live in `.env` (`DB_URI`), never in code.
- **`db_history.sh migrate-cloud`** — one command to push existing local `history.db` rows into the cloud database.
- **`.env.example`** — template documenting `DB_MODE`, `DB_FILE`, `DB_URI`, and runtime user settings.

### Changed
- `db_history.sh` now routes every query through `db_exec`, which dispatches to SQLite (`sqlite3`) or MySQL (`mysql`) based on `DB_MODE`.
- `db_history.sh` schema is created per backend (SQLite vs MySQL `CREATE TABLE`).
- `Dockerfile` — added `mariadb-client` package.
- `docker-compose.yml` — passes `DB_MODE` and `DB_URI` through from `.env`.
- All version references bumped to v3.0.0.

### Notes
- Only **history** is shared. Downloaded media files still land on the PC that downloaded them (`downloads/` is not synced).
- Duplicate detection becomes global in cloud mode: a video downloaded on PC 1 is skipped on PC 2.

## v2.1.1 (2026-07-19)
### Fixed
- **Race condition on queue file** — `process_queue_safe()` now takes a snapshot before processing, preventing URLs added mid-download from being lost. Preserves new entries added during processing.
- **Deprecated `--get-title` flag** — replaced with `--print` to stay compatible with latest yt-dlp.
- **Redundant yt-dlp requests after download** — file path and size are now obtained via local filesystem (`find` + `stat`) instead of making additional HTTP requests.
- **User/group creation in Alpine container (`entrypoint.sh`)** — fixed shell syntax error (`local` keyword outside function) and improved group conflict resolution when the target GID already exists as a system group.
- **Watch mode inefficiency** — installed `inotify-tools` in Docker image so watch mode uses event-driven notification instead of 5-second polling.
- **Missing `findutils` dependency** — added `findutils` to Docker image for `find -printf` support used in file detection.
- **Log files never cleaned** — logs older than 7 days are now automatically deleted.
- **Version inconsistency** — all files (`Dockerfile`, `docker-compose.yml`, `entrypoint.sh`, `run.sh`) now consistently reference v2.1.1.

### Changed
- `--merge-output-format mp4` moved from global `build_ytdlp_opts()` into per-category blocks (audio/twitter/default) for better clarity.
- `downloader.sh` — log cleanup routine added before download operations.
- `Dockerfile` — added `inotify-tools` and `findutils` packages.

## v2.1.0 (2026-07-07)
### Added
- **SQLite Download History** — migrated download history from text file to SQLite database
- **Duplicate detection** — URLs that have already been downloaded are automatically skipped
- **`db_history.sh`** — bash module for SQLite management (init, record, check, stats, migration)
- **Auto-migration** — automatic migration from `history.txt` to `history.db` on first run
- **Download stats** — view download statistics via `db_history.sh stats`

### Changed
- `downloader.sh` now uses SQLite to record history instead of a text file
- `Dockerfile` — added `sqlite` package

### Fixed
- **SQL parse error** — `file_size` from yt-dlp can be `NA` (non-numeric), now sanitized before storage

## v2.0.0 (2026-07-06)
### Added
- **Twitter/X support** — download videos from Twitter/X at the best quality
- **Auto-detect Twitter/X URLs** — automatically detects `twitter.com` and `x.com` URLs
- **Special yt-dlp options for Twitter** — format `best[ext=mp4]/best`, `embed-metadata`, `throttled-rate`
- **Entrypoint Twitter detection** — Twitter/X URLs recognized as download arguments
- **README Twitter guide** — comprehensive guide on cookies and downloading from Twitter/X

## v1.1.0 (2026-06-27)
### Added
- **Impersonation** — `curl_cffi` support for sites with strict protection
- **Progress bar** — displayed directly in the terminal during downloads

### Fixed
- **Cookies fix** — skip chown on `cookies.txt` to prevent read-only errors
- **Cookies path** — moved to `data/config/cookies.txt` (same folder as other config files)
- **Stray code** — removed leftover "New path for video" prompt

## v1.0.0 (2026-06-27)
### Added
- **Initial release** — YouTube Downloader fully automatic
- Docker Alpine + yt-dlp + ffmpeg
- Auto UID/GID — no more permission issues
- Watch mode — queue URLs are automatically downloaded
- Audio auto-detect (SoundCloud, Bandcamp, Spotify → MP3)
- Automatic logging & history
- Configuration via `settings.conf`
