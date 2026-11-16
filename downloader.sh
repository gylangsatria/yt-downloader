#!/bin/bash
# ======================================================
# YouTube/Twitter Downloader v3.0.0
# Fully Automatic Mode - Local/Cloud History
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

# === Parallel download tuning (override in .env) ===
# FRAGMENT_WORKERS - connections per download (yt-dlp -N). CDNs throttle per
#                    connection, so >1 is usually faster; too many can trip rate limits.
# HTTP_CHUNK_SIZE  - split plain HTTP downloads into parallel range requests
#                    (no effect on HLS/DASH, where -N does the work)
FRAGMENT_WORKERS="${FRAGMENT_WORKERS:-8}"
HTTP_CHUNK_SIZE="${HTTP_CHUNK_SIZE:-10M}"
[[ "$FRAGMENT_WORKERS" =~ ^[1-9][0-9]*$ ]] || FRAGMENT_WORKERS=8
[[ "$HTTP_CHUNK_SIZE" =~ ^[1-9][0-9]*[KMG]?$ ]] || HTTP_CHUNK_SIZE=10M

# === Retry / repair settings (override in .env) ===
# RESCAN_PROFILES     - re-queue profile/playlist URLs from history on start, so
#                       videos that failed earlier or were uploaded later get grabbed
# RETRY_FAILED_URLS   - re-queue single video URLs whose last attempt failed
# PARTIAL_MAX_AGE_H   - delete .part/.ytdl leftovers older than N hours (0 = any age)
# MAX_ATTEMPTS        - how many times a URL is retried (main + fallback per attempt)
# RETRY_SLEEP         - seconds to wait between attempts
RESCAN_PROFILES="${RESCAN_PROFILES:-true}"
RETRY_FAILED_URLS="${RETRY_FAILED_URLS:-true}"
PARTIAL_MAX_AGE_H="${PARTIAL_MAX_AGE_H:-6}"
MAX_ATTEMPTS="${MAX_ATTEMPTS:-3}"
RETRY_SLEEP="${RETRY_SLEEP:-30}"
[[ "$MAX_ATTEMPTS" =~ ^[1-9][0-9]*$ ]] || MAX_ATTEMPTS=3
[[ "$RETRY_SLEEP" =~ ^[0-9]+$ ]] || RETRY_SLEEP=30

LOG_FILE="$LOG_DIR/download_$(date +%Y%m%d_%H%M%S).log"

# === Logging ===
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }

# === Cookie file detection ===
COOKIES_FILE="$CONFIG_DIR/cookies.txt"

# Probes (extractor/title) need cookies too, otherwise PornHub serves the JS
# challenge page and the extractor is detected as "generic"
PROBE_COOKIES=()
[[ -f "$COOKIES_FILE" ]] && PROBE_COOKIES=(--cookies "$COOKIES_FILE")

# === Profile / playlist pages (PornHub model, user, channel, pornstar, playlist) ===
is_playlist_url() {
    echo "$1" | grep -qiE 'pornhub\.com/(model|users?|channels?|pornstars?|playlist)/'
}

# === Build yt-dlp options ===
# Arg 1 = "playlist" to download every entry of a profile/playlist page, else a single video
build_ytdlp_opts() {
    local pl_flag="--no-playlist"
    [[ "${1:-}" == "playlist" ]] && pl_flag="--yes-playlist"
    local opts=(
        "$pl_flag"
        "--no-warnings"
        "--restrict-filenames"
        "--progress"
        "-N" "$FRAGMENT_WORKERS"
        "--http-chunk-size" "$HTTP_CHUNK_SIZE"
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

# === Record a finished download (path = newest file in the output dir) ===
record_download() {
    local url="$1" title="$2" format="$3" output_dir="$4"
    local file_path file_size=0
    file_path=$(find "$output_dir" -maxdepth 1 -type f -newer "$QUEUE_FILE" -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -n1 | cut -d' ' -f2- || echo "")
    if [[ -z "$file_path" ]] || [[ ! -f "$file_path" ]]; then
        file_path=$(find "$output_dir" -maxdepth 1 -type f -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -n1 | cut -d' ' -f2- || echo "")
    fi
    [[ -n "$file_path" ]] && [[ -f "$file_path" ]] && file_size=$(stat -c%s "$file_path" 2>/dev/null || echo 0)
    db_record_success "$url" "$title" "$format" "$file_path" "$file_size" "0"
    log "[SUCCESS] Downloaded ($format): $title -> $output_dir"
}

# === Download single URL ===
download_url() {
    local url="$1"
    local format="$DEFAULT_FORMAT"
    local output_dir="$VIDEO_DIR"
    local is_audio=false

    # === Check if already downloaded (profiles are re-scanned: yt-dlp skips existing files, new uploads get grabbed) ===
    if db_url_exists "$url" && ! is_playlist_url "$url"; then
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

    # Auto-detect profile/playlist pages — every entry must be downloaded, not just the first
    local pl_flag="--no-playlist"
    local slug=""
    if is_playlist_url "$url"; then
        pl_flag="--yes-playlist"
        slug=$(echo "$url" | sed -nE 's#.*pornhub\.com/[a-z]+/([A-Za-z0-9_-]+).*#\1#p' | head -n1)
        log "Detected profile/playlist source${slug:+: $slug}"
    fi

    # Subfolder organization by extractor (profile pages: by profile name, no probe needed)
    local extractor
    if [[ -n "$slug" ]]; then
        extractor="pornhub/$slug"
    else
        extractor=$(yt-dlp "${PROBE_COOKIES[@]}" --no-playlist --print "extractor" "$url" 2>/dev/null | tr '[:upper:]' '[:lower:]' | sed 's/ /_/g')
    fi
    [[ -z "$extractor" ]] && extractor="generic"
    
    output_dir="$output_dir/$extractor"
    mkdir -p "$output_dir"

    # Build yt-dlp options (readarray to handle spaces safely)
    local opts=()
    while IFS= read -r line; do
        opts+=("$line")
    done < <(build_ytdlp_opts "${slug:+playlist}")

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

    # Title for history — profiles use the slug, no extra yt-dlp request
    local title
    if [[ -n "$slug" ]]; then
        title="$slug"
    else
        title=$(yt-dlp "${PROBE_COOKIES[@]}" --no-playlist --print "%(title)s" "$url" 2>/dev/null || echo "unknown")
    fi

    # Execute download — show progress in terminal, log everything.
    # MAX_ATTEMPTS / RETRY_SLEEP from .env: PornHub's JS challenge and 5xx pages are
    # intermittent, so a retry usually gets through. Existing files are skipped on
    # every attempt, so each pass only fetches what is still missing.
    local attempt
    for (( attempt = 1; attempt <= MAX_ATTEMPTS; attempt++ )); do
        if [[ "$attempt" -gt 1 ]]; then
            log "[RETRY] Attempt $attempt/$MAX_ATTEMPTS in ${RETRY_SLEEP}s: $url"
            sleep "$RETRY_SLEEP"
        fi

        if yt-dlp "${opts[@]}" 2> >(tee -a "$LOG_FILE" >&2); then
            record_download "$url" "$title" "best" "$output_dir"
            return 0
        fi
        log "[ERROR] Failed (attempt $attempt/$MAX_ATTEMPTS): $url"

        # Retry with basic format; same filename rules as the main attempt, otherwise
        # yt-dlp sees different names and downloads duplicates instead of skipping
        local fallback_opts=("$pl_flag" --no-warnings --restrict-filenames -N "$FRAGMENT_WORKERS" --merge-output-format mp4 -f "best" -P "$output_dir" -o "%(title).200s.%(ext)s")
        [[ -f "$COOKIES_FILE" ]] && fallback_opts+=(--cookies "$COOKIES_FILE")
        fallback_opts+=("$url")
        if yt-dlp "${fallback_opts[@]}" 2> >(tee -a "$LOG_FILE" >&2); then
            record_download "$url" "$title" "fallback" "$output_dir"
            return 0
        fi
        log "[ERROR] Fallback failed (attempt $attempt/$MAX_ATTEMPTS): $url"
    done

    db_record_failure "$url" "$title" "best"
    log "[FAILED] All attempts failed: $url"
    return 1
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

# === Housekeeping: delete stale partial downloads so yt-dlp restarts them clean ===
purge_stale_partials() {
    [[ "$PARTIAL_MAX_AGE_H" =~ ^[0-9]+$ ]] || return 0
    local removed
    # Fresh partials are left alone so an in-flight download is never touched
    removed=$(find "$VIDEO_DIR" "$MUSIC_DIR" -type f \
        \( -name '*.part' -o -name '*.part-Frag*' -o -name '*.ytdl' \) \
        -mmin +$(( PARTIAL_MAX_AGE_H * 60 )) -print -delete 2>/dev/null | wc -l)
    [[ "$removed" -gt 0 ]] && log "[CLEAN] Removed $removed stale partial file(s) older than ${PARTIAL_MAX_AGE_H}h"
    return 0
}

# === Re-queue work from history (profiles every start, failed singles too) ===
queue_add() {
    grep -qxF "$1" "$QUEUE_FILE" 2>/dev/null && return 0
    echo "$1" >> "$QUEUE_FILE"
    log "[RETRY] Re-queued: $1"
}

requeue_from_history() {
    local url
    if [[ "$RESCAN_PROFILES" == "true" ]]; then
        while IFS= read -r url; do
            [[ -z "$url" ]] && continue
            is_playlist_url "$url" || continue
            queue_add "$url"
        done < <(db_list_urls)
    fi
    if [[ "$RETRY_FAILED_URLS" == "true" ]]; then
        while IFS= read -r url; do
            [[ -z "$url" ]] && continue
            is_playlist_url "$url" && continue
            queue_add "$url"
        done < <(db_list_urls failed)
    fi
    return 0
}

# === Watch mode: monitor queue file ===
watch_mode() {
    log "=== Watch mode started ==="
    log "Watching: $QUEUE_FILE"
    log "Add URLs to $QUEUE_FILE (one per line)"
    log "Output: Videos -> $VIDEO_DIR | Music -> $MUSIC_DIR"
    echo ""

    # Retry/repair pass before the first queue run (all controlled from .env)
    purge_stale_partials
    requeue_from_history

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
