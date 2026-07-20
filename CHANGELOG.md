# Changelog

## v2.1.2 (2026-07-20)
### Fixed
- **SQLite separator conflict** — Used ASCII Unit Separator (`\x1f`) instead of `|` for internal database communication, fixing broken history checks for titles containing pipes.
- **Protected video titles** — Added cookie support to title extraction, preventing "unknown" titles when downloading from sites requiring authentication (like Twitter/X).
- **Reliable file path detection** — Replaced fragile `find -newer` logic with native `yt-dlp --print after_move:filepath` for 100% accurate file tracking even if the queue file is modified during download.
- **SQLite robustness** — Added checks for empty database results to prevent bash syntax errors if the database is locked or inaccessible.
- **Security hardening** — Added sanitization for the `limit` argument in `db_history.sh`.
- **Version consistency** — Synced version strings across all scripts and configuration files.

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
