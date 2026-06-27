# YouTube Downloader v1.0.0

> **Automatic YouTube downloader** — Tinggal run, URL otomatis terdownload ke folder host.

![Docker](https://img.shields.io/badge/Docker-Alpine-blue?logo=docker)
![yt-dlp](https://img.shields.io/badge/yt--dlp-latest-green)
![License](https://img.shields.io/badge/license-MIT-orange)

---

## Fitur

- **Auto UID/GID** — file hasil download langsung bisa diakses dari host (no permission issues)
- **Dual mode** — download via argument atau queue file
- **Watch mode** — tinggal tulis URL di `data/config/queue.txt`, container auto-proses
- **Audio auto-detect** — URL dari SoundCloud/Bandcamp/Spotify otomatis jadi MP3
- **Fallback otomatis** — coba berbagai format jika gagal
- **Logging** — semua aktivitas tercatat di `data/logs/`

---

## Cara Pakai

### 1. Start container

```bash
./run.sh
```

### 2a. Download langsung

```bash
./run.sh "https://youtube.com/watch?v=..."
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

## Struktur Folder

```
yt-downloader/
├── Dockerfile              # Alpine + yt-dlp + ffmpeg
├── docker-compose.yml      # Auto UID/GID
├── entrypoint.sh           # Runtime user creation
├── downloader.sh           # Main downloader (watch/argument mode)
├── run.sh                  # One-command launcher
├── downloads/
│   ├── Videos/             # Hasil download video
│   └── Music/              # Hasil download audio (MP3)
├── data/
│   ├── config/
│   │   ├── settings.conf   # Konfigurasi format
│   │   └── queue.txt       # Queue URL (tulis URL di sini)
│   └── logs/               # Log otomatis
├── .gitignore
└── .dockerignore
```

---

## Konfigurasi

Edit `data/config/settings.conf`:

```ini
DEFAULT_FORMAT="bv*+ba/best"     # Format video terbaik
AUDIO_FORMAT="ba/bestaudio"      # Format audio terbaik
```

---

## Catatan

- Container jalan di background (`restart: unless-stopped`)
- File download otomatis ter-ignore dari git
- History download tersimpan di `data/config/history.txt`

---

## Changelog

### v1.0.0 (2026-06-27)
- **Rilis perdana** — YouTube Downloader fully automatic
- Docker Alpine + yt-dlp + ffmpeg
- Auto UID/GID — no more permission issues
- Watch mode — queue URL otomatis terdownload
- Audio auto-detect (SoundCloud, Bandcamp, Spotify → MP3)
- Logging & history otomatis
- Konfigurasi via `settings.conf`

---

## Credit

**Dibuat oleh [gylangsatria](https://github.com/gylangsatria)**

Powered by:
- [yt-dlp](https://github.com/yt-dlp/yt-dlp)
- [ffmpeg](https://ffmpeg.org/)
- [Alpine Linux](https://alpinelinux.org/)
