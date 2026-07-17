# YouTube Downloader v2.1.0

> **Automatic YouTube Downloader** — Just run it, URLs get downloaded automatically to your host folder.

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
- **SQLite History** — Download history stored neatly in a SQLite database
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
├── db_history.sh           # SQLite download history module
├── run.sh                  # One-command launcher
├── downloads/
│   ├── Videos/             # Video downloads
│   └── Music/              # Audio downloads (MP3)
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

## SQLite Download History

Since v2.1.0, download history is stored in a **SQLite database** (`data/config/history.db`).
Migration from `history.txt` happens automatically on first run.

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
```

> **Note:** The `history.db` database is automatically created and migrated from `history.txt` the first time the container runs. No manual setup required.

---

## Configuration

Edit `data/config/settings.conf`:

```ini
DEFAULT_FORMAT="bv*+ba/best"     # Best video format
AUDIO_FORMAT="ba/bestaudio"      # Best audio format
```

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

## Notes

- Container runs in the background (`restart: unless-stopped`)
- Downloaded files are automatically git-ignored
- Download history is stored in SQLite (`data/config/history.db`) — automatic migration from `history.txt`
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
