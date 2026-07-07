# Changelog

## v2.1.0 (2026-07-07)
### Added
- **SQLite Download History** — riwayat download pindah dari text file ke SQLite database
- **Duplicate detection** — URL yang sudah pernah di-download otomatis di-skip
- **`db_history.sh`** — modul bash untuk manajemen SQLite (init, record, check, stats, migrasi)
- **Auto-migration** — migrasi otomatis dari `history.txt` ke `history.db` saat pertama jalan
- **Download stats** — lihat statistik download via `db_history.sh stats`

### Changed
- `downloader.sh` sekarang menggunakan SQLite untuk catat history, bukan text file
- `Dockerfile` — tambah package `sqlite`

### Fixed
- **SQL parse error** — file_size dari yt-dlp bisa berupa `NA` (non-numeric), sekarang di-sanitasi sebelum disimpan

## v2.0.0 (2026-07-06)
### Added
- **Twitter/X support** — download video dari Twitter/X dengan kualitas terbaik
- **Auto-detect Twitter/X URLs** — otomatis mendeteksi URL `twitter.com` dan `x.com`
- **Special yt-dlp options for Twitter** — format `best[ext=mp4]/best`, `embed-metadata`, `throttled-rate`
- **Entrypoint Twitter detection** — URL Twitter/X dikenali sebagai argumen download
- **README Twitter guide** — panduan lengkap cookies & cara download dari Twitter/X

## v1.1.0 (2026-06-27)
### Added
- **Impersonation** — dukungan `curl_cffi` untuk situs dengan proteksi ketat
- **Progress bar** — tampil langsung di terminal saat download

### Fixed
- **Cookies fix** — skip chown pada cookies.txt biar gak error read-only
- **Cookies path** — pindah ke `data/config/cookies.txt` (satu folder dengan config lain)
- **Stray code** — hapus prompt "Path baru untuk video" yang nyangkut

## v1.0.0 (2026-06-27)
### Added
- **Rilis perdana** — YouTube Downloader fully automatic
- Docker Alpine + yt-dlp + ffmpeg
- Auto UID/GID — no more permission issues
- Watch mode — queue URL otomatis terdownload
- Audio auto-detect (SoundCloud, Bandcamp, Spotify → MP3)
- Logging & history otomatis
- Konfigurasi via `settings.conf`
