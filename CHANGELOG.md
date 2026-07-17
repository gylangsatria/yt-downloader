# Changelog

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
