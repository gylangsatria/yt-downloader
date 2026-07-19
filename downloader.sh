#!/bin/bash
# ======================================================
# YouTube/Twitter Downloader v2.1.0
# Fully Automatic Mode - SQLite History
# ======================================================
# Author  : gylangsatria
# GitHub  : https://github.com/gylangsatria
# ======================================================

# === Configuration ===
VIDEO_DIR="${VIDEO_DIR:-/app/downloads/Videos}"
MUSIC_DIR="${MUSIC_DIR:-/app/downloads/Music}"
LOG_DIR="${LOG_DIR:-/app/.yt-dlp-logs}"
CONFIG_DIR="${CONFIG_DIR:-/app/.yt-dlp-config}"
QUEUE_FILE="$CONFIG_DIR/queue.txt"
HISTORY_FILE="$CONFIG_DIR/history.txt"
CONFIG_FILE="$CONFIG_DIR/settings.conf"
DB_FILE="${DB_FILE:-$CONFIG_DIR/history.db}"

mkdir -p "$VIDEO_DIR" "$MUSIC_DIR" "$LOG_DIR" "$CONFIG_DIR"

# === Source DB module ===
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/db_history.sh"

# === Initialize database and migrate old history ===
db_init
if [[ -f "$HISTORY_FILE" ]] && [[ ! -f "$CONFIG_DIR/.migrated" ]]; then
    db_migrate_from_txt "$HISTORY_FILE"
    touch "$CONFIG_DIR/.migrated"
fi

# === Load config ===
[[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE"

# Default format: best video+audio
DEFAULT_FORMAT="${DEFAULT_FORMAT:-bv*+ba/best}"
AUDIO_FORMAT="${AUDIO_FORMAT:-ba/bestaudio}"

LOG_FILE="$LOG_DIR/download_$(date +%Y%m%d_%H%M%S).log"

# === Logging ===
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }

# === Cookie file detection ===
COOKIES_FILE="$CONFIG_DIR/cookies.txt"

# === Build yt-dlp options ===
build_ytdlp_opts() {
    local opts=(
        "--no-playlist"
        "--no-warnings"
        "--restrict-filenames"
        "--progress"
    )

    # Auto-use cookies.txt if available
    if [[ -f "$COOKIES_FILE" ]]; then
        # Log to stderr so it doesn't leak into the options array
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Using cookies: $COOKIES_FILE" | tee -a "$LOG_FILE" >&2
        opts+=("--cookies" "$COOKIES_FILE")
    fi

    # Return as array-safe output
    printf '%s\n' "${opts[@]}"
}

# Clean up logs older than 7 days
find "$LOG_DIR" -name 'download_*.log' -mtime +7 -delete 2>/dev/null || true

# === Download single URL ===
download_url() {
    local url="$1"
    local format="$DEFAULT_FORMAT"
    local output_dir="$VIDEO_DIR"
    local is_audio=false

    # === Check if already downloaded ===
    if db_url_exists "$url"; then
        local existing_info
        existing_info=$(db_get_info "$url")
        local existing_title
        existing_title=$(echo "$existing_info" | cut -d'|' -f1)
        local existing_status
        existing_status=$(echo "$existing_info" | cut -d'|' -f3)
        local existing_date
        existing_date=$(echo "$existing_info" | cut -d'|' -f5)

        if [[ "$existing_status" == "success" ]]; then
            log "[SKIP] Already downloaded on $existing_date: ${existing_title:-$url}"
            return 0
        elif [[ "$existing_status" == "failed" ]]; then
            log "[RETRY] Previously failed on $existing_date, retrying: $url"
        fi
    fi

    log "====== Download started: $url ======"

    # Auto-detect audio-only URLs (music sites)
    if echo "$url" | grep -qiE '(soundcloud|bandcamp|spotify|music\.)'; then
        format="$AUDIO_FORMAT"
        output_dir="$MUSIC_DIR"
        is_audio=true
        log "Detected audio source"
    fi

    # Auto-detect Twitter/X URLs — they need special options
    local is_twitter=false
    if echo "$url" | grep -qiE '(twitter\.com|x\.com)'; then
        is_twitter=true
        log "Detected Twitter/X source"
    fi

    # Build yt-dlp options (readarray to handle spaces safely)
    local opts=()
    while IFS= read -r line; do
        opts+=("$line")
    done < <(build_ytdlp_opts)

    # Audio options
    if [[ "$is_audio" == "true" ]]; then
        opts+=("--merge-output-format" "mp4")
        opts+=("-x" "--audio-format" "mp3" "--audio-quality" "0")
        opts+=("--add-metadata" "--embed-thumbnail")
        opts+=("-f" "$AUDIO_FORMAT")
    elif [[ "$is_twitter" == "true" ]]; then
        # Twitter/X: download all available qualities, prefer highest quality, embed metadata
        opts+=("--merge-output-format" "mp4")
        opts+=("-f" "best[ext=mp4]/best")
        opts+=("--embed-metadata")
        opts+=("--throttled-rate" "100M")
    else
        opts+=("--merge-output-format" "mp4")
        opts+=("-f" "$DEFAULT_FORMAT")
    fi

    opts+=("-P" "$output_dir")
    opts+=("-o" "%(title).200s.%(ext)s")
    opts+=("$url")

    # Get title for history — use --print instead of deprecated --get-title
    local title
    title=$(yt-dlp --no-playlist --print "%(title)s" "$url" 2>/dev/null || echo "unknown")

    # Execute download — show progress in terminal, log everything
    if yt-dlp "${opts[@]}" 2> >(tee -a "$LOG_FILE" >&2); then
        # Get the actual file path without an extra yt-dlp request:
        # Scan the output dir for the most recently modified file
        local file_path=""
        local file_size=0
        file_path=$(find "$output_dir" -maxdepth 1 -type f -newer "$QUEUE_FILE" -printf '%T@ %p\0' 2>/dev/null | sort -rnz | head -z -n1 | tr '\0' '\n' | cut -d' ' -f2- || echo "")
        if [[ -z "$file_path" ]] || [[ ! -f "$file_path" ]]; then
            # Fallback: just get the most recently modified file in the dir
            file_path=$(find "$output_dir" -maxdepth 1 -type f -printf '%T@ %p\0' 2>/dev/null | sort -rnz | head -z -n1 | tr '\0' '\n' | cut -d' ' -f2- || echo "")
        fi
        if [[ -n "$file_path" ]] && [[ -f "$file_path" ]]; then
            file_size=$(stat -c%s "$file_path" 2>/dev/null || echo 0)
        fi

        # Record to SQLite
        db_record_success "$url" "$title" "best" "$file_path" "$file_size" "0"
        log "[SUCCESS] Downloaded: $title -> $output_dir"
        return 0
    else
        log "[ERROR] Failed: $url"
        db_record_failure "$url" "$title" "best"

        # Retry with basic format
        log "[RETRY] Trying fallback format..."
        local fallback_opts=(--no-playlist --merge-output-format mp4 -f "best" -P "$output_dir" -o "%(title).200s.%(ext)s")
        [[ -f "$COOKIES_FILE" ]] && fallback_opts+=(--cookies "$COOKIES_FILE")
        fallback_opts+=("$url")
        if yt-dlp "${fallback_opts[@]}" 2> >(tee -a "$LOG_FILE" >&2); then
            local file_path=""
            local file_size=0
            file_path=$(find "$output_dir" -maxdepth 1 -type f -printf '%T@ %p\0' 2>/dev/null | sort -rnz | head -z -n1 | tr '\0' '\n' | cut -d' ' -f2- || echo "")
            if [[ -n "$file_path" ]] && [[ -f "$file_path" ]]; then
                file_size=$(stat -c%s "$file_path" 2>/dev/null || echo 0)
            fi
            db_record_success "$url" "$title" "fallback" "$file_path" "$file_size" "0"
            log "[SUCCESS] Downloaded (fallback): $title -> $output_dir"
            return 0
        else
            log "[FAILED] All attempts failed: $url"
            return 1
        fi
    fi
}

# === Proper queue processing — line-by-line to avoid race conditions ===
process_queue_safe() {
    if [[ ! -f "$QUEUE_FILE" ]]; then
        touch "$QUEUE_FILE"
        return
    fi

    local processed=0

    # Snapshot the current queue and process only those lines
    local snapshot
    snapshot=$(mktemp "$QUEUE_FILE.snapshot.XXXXXX") 2>/dev/null || snapshot="${QUEUE_FILE}.snapshot"
    cp "$QUEUE_FILE" "$snapshot" 2>/dev/null

    while IFS= read -r line || [[ -n "$line" ]]; do
        line="$(echo "$line" | tr -d '\r' | xargs)"
        [[ -z "$line" ]] && continue
        [[ "$line" == \#* ]] && continue

        ((processed++))
        download_url "$line"
    done < "$snapshot"

    # Remove only the lines that were in the snapshot from the queue
    # This preserves any URLs added while processing was running
    if [[ -f "$snapshot" ]]; then
        local temp_queue
        temp_queue=$(mktemp "$QUEUE_FILE.tmp.XXXXXX") 2>/dev/null || temp_queue="${QUEUE_FILE}.tmp"
        while IFS= read -r line || [[ -n "$line" ]]; do
            line="$(echo "$line" | tr -d '\r' | xargs)"
            [[ -z "$line" ]] && continue
            # Skip lines that were in the snapshot (already processed)
            if ! grep -qF "$line" "$snapshot" 2>/dev/null; then
                echo "$line" >> "$temp_queue"
            fi
        done < "$QUEUE_FILE"
        mv "$temp_queue" "$QUEUE_FILE" 2>/dev/null || cp "$temp_queue" "$QUEUE_FILE"
        rm -f "$temp_queue" 2>/dev/null
    fi

    rm -f "$snapshot" "${QUEUE_FILE}.snapshot"* 2>/dev/null

    if [[ "$processed" -gt 0 ]]; then
        log "Queue processed: $processed item(s)"
    fi
}

# === Watch mode: monitor queue file ===
watch_mode() {
    log "=== Watch mode started ==="
    log "Watching: $QUEUE_FILE"
    log "Add URLs to $QUEUE_FILE (one per line)"
    log "Output: Videos -> $VIDEO_DIR | Music -> $MUSIC_DIR"
    echo ""

    # Initial queue processing
    process_queue_safe

    # Monitor for changes using inotify if available, else poll
    if command -v inotifywait &> /dev/null; then
        while inotifywait -q -e close_write,moved_to "$QUEUE_FILE" 2>/dev/null; do
            sleep 1
            process_queue_safe
        done
    else
        local last_mtime=$(stat -c %Y "$QUEUE_FILE" 2>/dev/null || echo 0)
        while true; do
            local current_mtime=$(stat -c %Y "$QUEUE_FILE" 2>/dev/null || echo 0)
            if [[ "$current_mtime" -gt "$last_mtime" ]]; then
                last_mtime="$current_mtime"
                process_queue_safe
            fi
            sleep 5
        done
    fi
}

# === Main ===
if [[ $# -gt 0 ]]; then
    # URL(s) provided as arguments - download and exit
    for url in "$@"; do
        download_url "$url"
    done
else
    # No arguments - start watch mode
    watch_mode
fi
