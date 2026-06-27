#!/bin/bash
# ======================================================
# YouTube Downloader v1.0.0
# Fully Automatic Mode
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

mkdir -p "$VIDEO_DIR" "$MUSIC_DIR" "$LOG_DIR" "$CONFIG_DIR"

# === Load config ===
[[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE"

# Default format: best video+audio
DEFAULT_FORMAT="${DEFAULT_FORMAT:-bv*+ba/best}"
AUDIO_FORMAT="${AUDIO_FORMAT:-ba/bestaudio}"

LOG_FILE="$LOG_DIR/download_$(date +%Y%m%d_%H%M%S).log"

# === Logging ===
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }

# === Download single URL ===
download_url() {
    local url="$1"
    local format="$DEFAULT_FORMAT"
    local output_dir="$VIDEO_DIR"
    local is_audio=false

    log "====== Download started: $url ======"

    # Auto-detect audio-only URLs (music sites)
    if echo "$url" | grep -qiE '(soundcloud|bandcamp|spotify|music\.)'; then
        format="$AUDIO_FORMAT"
        output_dir="$MUSIC_DIR"
        is_audio=true
        log "Detected audio source"
    fi

    # Build yt-dlp options
    local opts=(
        "--no-playlist"
        "--merge-output-format" "mp4"
        "--no-warnings"
        "--restrict-filenames"
        "--progress"
    )

    # Audio options
    if [[ "$is_audio" == "true" ]]; then
        opts+=("-x" "--audio-format" "mp3" "--audio-quality" "0")
        opts+=("--add-metadata" "--embed-thumbnail")
        opts+=("-f" "$AUDIO_FORMAT")
    else
        opts+=("-f" "$DEFAULT_FORMAT")
    fi

    opts+=("-P" "$output_dir")
    opts+=("-o" "%(title).200s.%(ext)s")
    opts+=("$url")

    # Get filename first for history
    local title=$(yt-dlp --no-playlist --get-title "$url" 2>/dev/null || echo "unknown")

    # Execute download
    if yt-dlp "${opts[@]}" 2>> "$LOG_FILE" > /dev/null; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') | $url | best | $title" >> "$HISTORY_FILE"
        log "[SUCCESS] Downloaded: $title -> $output_dir"
        return 0
    else
        log "[ERROR] Failed: $url"
        # Retry with basic format
        log "[RETRY] Trying fallback format..."
        if yt-dlp --no-playlist -f "best" -P "$output_dir" -o "%(title).200s.%(ext)s" "$url" 2>> "$LOG_FILE" > /dev/null; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') | $url | fallback | $title" >> "$HISTORY_FILE"
            log "[SUCCESS] Downloaded (fallback): $title -> $output_dir"
            return 0
        else
            log "[FAILED] All attempts failed: $url"
            return 1
        fi
    fi
}

# === Proper queue processing ===
process_queue_safe() {
    if [[ ! -f "$QUEUE_FILE" ]]; then
        touch "$QUEUE_FILE"
        return
    fi

    local processed=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        line="$(echo "$line" | tr -d '\r' | xargs)"
        [[ -z "$line" ]] && continue
        [[ "$line" == \#* ]] && continue

        ((processed++))
        download_url "$line"
    done < "$QUEUE_FILE"

    # Clear the queue after processing
    > "$QUEUE_FILE"

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
                    read -p "Path baru untuk video (relative atau absolute): " new_video
