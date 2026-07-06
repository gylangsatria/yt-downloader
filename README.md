# YouTube Downloader v2.0.0

> **Automatic YouTube & Twitter/X Downloader** — Tinggal run, URL otomatis terdownload ke folder host.

![Docker](https://img.shields.io/badge/Docker-Alpine-blue?logo=docker)
![yt-dlp](https://img.shields.io/badge/yt--dlp-latest-green)
![License](https://img.shields.io/badge/license-MIT-orange)

---

## Fitur

- **Auto UID/GID** — file hasil download langsung bisa diakses dari host (no permission issues)
- **Dual mode** — download via argument atau queue file
- **Watch mode** — tinggal tulis URL di `data/config/queue.txt`, container auto-proses
- **Audio auto-detect** — URL dari SoundCloud/Bandcamp/Spotify otomatis jadi MP3
- **Twitter/X support** — download video dari Twitter/X dengan kualitas terbaik
- **Fallback otomatis** — coba berbagai format jika gagal
- **Impersonation** — dukungan `curl_cffi` untuk situs dengan proteksi ketat
- **Progress bar** — tampil langsung di terminal saat download
- **Cookies support** — export cookies browser untuk akses situs dengan proteksi
- **Logging** — semua aktivitas tercatat di `data/logs/`

---

## Cara Pakai

### 1. Start container

```bash
./run.sh
```

### 2a. Download langsung

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
│   │   ├── queue.txt       # Queue URL (tulis URL di sini)
│   │   ├── history.txt     # Riwayat download
│   │   └── cookies.txt     # Cookies browser (optional)
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

## Twitter/X — Catatan Penting

Twitter/X **membutuhkan cookies** dari akun yang sudah login. Video publik sekalipun sering tidak bisa di-download tanpa cookies karena pembatasan dari Twitter.

**Langkah-langkah:**
1. Buka Twitter/X.com di browser
2. Login ke akun Twitter (akun gratisan sudah cukup)
3. Export cookies ke `data/config/cookies.txt` (lihat panduan cookies di bawah)
4. Download URL Twitter/X seperti biasa

```bash
./run.sh "https://x.com/i/status/2072712422025023645"
```

> **Tips:** Jika muncul error "Twitter requires logging in", berarti cookies-mu expired. Export ulang cookies dari browser.

---

## Cookies — Akses Situs dengan Proteksi

Beberapa situs dengan proteksi Cloudflare atau yang butuh autentikasi (seperti Twitter/X) butuh **cookies browser** untuk bisa di-download.

### Cara 1: Export cookies.txt (disarankan)

1. Install ekstensi browser:
   - **Chrome/Edge**: [Get cookies.txt LOCALLY](https://chrome.google.com/webstore/detail/get-cookiestxt-locally/cclelndahbckbenkjhflpdbgdldlbecc)
   - **Firefox**: [cookies.txt](https://addons.mozilla.org/en-US/firefox/addon/cookies-txt/)

2. Buka situs target, login, lalu export cookies → simpan sebagai `data/config/cookies.txt`

3. Selesai! Container otomatis pakai cookies itu.

### Cara 2: Extract via command line (Python)

```bash
# Install browsercookie
pip install browsercookie

# Ekstrak cookies dari browser (Chrome/Edge/Firefox)
python3 -c "
import browsercookie, http.cookiejar
cj = browsercookie.chrome()  # ganti .chrome() jadi .firefox() kalo pake Firefox
with open('data/config/cookies.txt', 'w') as f:
    for c in cj:
        f.write(f'{c.domain}\tTRUE\t{c.path}\tFALSE\t{int(c.expires if c.expires else 0)}\t{c.name}\t{c.value}\n')
print('Cookies saved to data/config/cookies.txt')
"
```

> **Catatan:** `data/config/cookies.txt` sudah di-ignore git (via `.gitignore`).

---

## Catatan

- Container jalan di background (`restart: unless-stopped`)
- File download otomatis ter-ignore dari git
- History download tersimpan di `data/config/history.txt`

---

## Changelog

Lihat [CHANGELOG.md](CHANGELOG.md) untuk riwayat perubahan lengkap.

---

## Credit

**Dibuat oleh [gylangsatria](https://github.com/gylangsatria)**

Powered by:
- [yt-dlp](https://github.com/yt-dlp/yt-dlp)
- [ffmpeg](https://ffmpeg.org/)
- [Alpine Linux](https://alpinelinux.org/)
