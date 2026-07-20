#!/bin/bash
# ======================================================
# SQLite Download History Module
# ======================================================
# Author  : gylangsatria
# GitHub  : https://github.com/gylangsatria
# ======================================================
#
# Provides functions to track download history in SQLite,
# replacing the plain-text history.txt approach.
#
# Database schema:
#   downloads (
#     id          INTEGER PRIMARY KEY AUTOINCREMENT,
#     url         TEXT NOT NULL UNIQUE,
#     title       TEXT,
#     format      TEXT,
#     status      TEXT DEFAULT 'success',
#     file_path   TEXT,
#     file_size   INTEGER,
#     duration    INTEGER,
#     downloaded_at TEXT DEFAULT (datetime('now','localtime'))
#   )
#
# Environment variables:
#   DB_FILE  - Path to SQLite database (default: /app/.yt-dlp-config/history.db)
# ======================================================

DB_FILE="${DB_FILE:-/app/.yt-dlp-config/history.db}"

# === Initialize database ===
db_init() {
    sqlite3 "$DB_FILE" <<'SQL'
CREATE TABLE IF NOT EXISTS downloads (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    url             TEXT NOT NULL UNIQUE,
    title           TEXT DEFAULT '',
    format          TEXT DEFAULT '',
    status          TEXT DEFAULT 'success',
    file_path       TEXT DEFAULT '',
    file_size       INTEGER DEFAULT 0,
    duration        INTEGER DEFAULT 0,
    downloaded_at   TEXT DEFAULT (datetime('now','localtime'))
);
CREATE INDEX IF NOT EXISTS idx_downloads_url ON downloads(url);
CREATE INDEX IF NOT EXISTS idx_downloads_status ON downloads(status);
CREATE INDEX IF NOT EXISTS idx_downloads_downloaded_at ON downloads(downloaded_at);
SQL
}

# === Check if URL already exists in database ===
# Returns 0 (true) if exists, 1 (false) if not
db_url_exists() {
    local url="$1"
    local count
    count=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM downloads WHERE url = '$(sqlite3_escape "$url")'" 2>/dev/null)
    [[ -n "$count" ]] && [[ "$count" -gt 0 ]]
}

# === Sanitize numeric value (force to integer, default 0) ===
sanitize_num() {
    local val="$1"
    # Remove non-numeric characters except leading minus
    val="${val//[^0-9]/}"
    echo "${val:-0}"
}

# === Record a successful download ===
db_record_success() {
    local url="$1"
    local title="$2"
    local format="$3"
    local file_path="$4"
    local file_size
    file_size=$(sanitize_num "$5")
    local duration
    duration=$(sanitize_num "$6")

    sqlite3 "$DB_FILE" <<SQL
INSERT OR REPLACE INTO downloads (url, title, format, status, file_path, file_size, duration, downloaded_at)
VALUES (
    '$(sqlite3_escape "$url")',
    '$(sqlite3_escape "$title")',
    '$(sqlite3_escape "$format")',
    'success',
    '$(sqlite3_escape "$file_path")',
    $file_size,
    $duration,
    datetime('now','localtime')
);
SQL
}

# === Record a failed download attempt ===
db_record_failure() {
    local url="$1"
    local title="$2"
    local format="$3"

    sqlite3 "$DB_FILE" <<SQL
INSERT OR REPLACE INTO downloads (url, title, format, status, downloaded_at)
VALUES (
    '$(sqlite3_escape "$url")',
    '$(sqlite3_escape "$title")',
    '$(sqlite3_escape "$format")',
    'failed',
    datetime('now','localtime')
);
SQL
}

# === Get download info for a URL ===
# Prints fields separated by ASCII Unit Separator (hex 1F)
db_get_info() {
    local url="$1"
    # Use ASCII Unit Separator \x1F as it is extremely unlikely to be in a title
    sqlite3 "$DB_FILE" "SELECT title, format, status, file_path, downloaded_at FROM downloads WHERE url = '$(sqlite3_escape "$url")'" -separator $'\x1f'
}

# === List recent downloads ===
db_list_recent() {
    local limit=$(sanitize_num "${1:-20}")
    sqlite3 "$DB_FILE" "SELECT id, url, title, status, downloaded_at FROM downloads ORDER BY downloaded_at DESC LIMIT $limit" -separator ' | ' -header
}

# === Show download statistics ===
db_stats() {
    sqlite3 "$DB_FILE" <<'SQL'
SELECT 'total'     AS metric, COUNT(*)               AS value FROM downloads
UNION ALL
SELECT 'success'   AS metric, COUNT(*)               AS value FROM downloads WHERE status = 'success'
UNION ALL
SELECT 'failed'    AS metric, COUNT(*)               AS value FROM downloads WHERE status = 'failed'
UNION ALL
SELECT 'unique'    AS metric, COUNT(DISTINCT url)    AS value FROM downloads
UNION ALL
SELECT 'today'     AS metric, COUNT(*)               AS value FROM downloads WHERE date(downloaded_at) = date('now','localtime');
SQL
}

# === Get the title from history if previously downloaded ===
db_get_title() {
    local url="$1"
    sqlite3 "$DB_FILE" "SELECT title FROM downloads WHERE url = '$(sqlite3_escape "$url")' AND title != '' ORDER BY downloaded_at DESC LIMIT 1"
}

# === Escape single quotes for SQLite ===
sqlite3_escape() {
    local str="$1"
    str="${str//\'/\'\'}"
    echo "$str"
}

# === Migrate from old history.txt to SQLite ===
db_migrate_from_txt() {
    local history_file="${1:-/app/.yt-dlp-config/history.txt}"

    if [[ ! -f "$history_file" ]]; then
        return 0
    fi

    local migrated=0
    local line date_time url format title

    while IFS= read -r line || [[ -n "$line" ]]; do
        line="$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        [[ -z "$line" ]] && continue
        [[ "$line" == \#* ]] && continue

        # Format: 2026-07-07 03:17:56 | https://x.com/... | best | title here
        # Split on " | " — datetime is first field, url starts with http, then format, rest is title
        # Use a more robust approach: match pattern "YYYY-MM-DD HH:MM:SS | <url> | <format> | <rest>"
        if [[ "$line" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]][0-9]{2}:[0-9]{2}:[0-9]{2})\ \|\ (https?://[^ ]+)\ \|\ ([^|]+)\ \|\ (.*)$ ]]; then
            date_time="${BASH_REMATCH[1]}"
            url="${BASH_REMATCH[2]}"
            format="$(echo "${BASH_REMATCH[3]}" | xargs)"
            title="$(echo "${BASH_REMATCH[4]}" | xargs)"

            sqlite3 "$DB_FILE" "INSERT OR IGNORE INTO downloads (url, title, format, status, downloaded_at) VALUES ('$(sqlite3_escape "$url")', '$(sqlite3_escape "$title")', '$(sqlite3_escape "$format")', 'success', '$(sqlite3_escape "$date_time")');" 2>/dev/null
            ((migrated++))
        fi
    done < "$history_file"

    echo "[DB] Migrated $migrated entries from history.txt to SQLite database"
}

# === Main: run if executed directly ===
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-help}" in
        init)
            db_init
            echo "[DB] Database initialized: $DB_FILE"
            ;;
        exists)
            db_url_exists "$2" && echo "yes" || echo "no"
            ;;
        record)
            shift
            db_record_success "$@"
            ;;
        fail)
            db_record_failure "$2" "$3" "$4"
            ;;
        info)
            db_get_info "$2"
            ;;
        recent)
            db_list_recent "${2:-20}"
            ;;
        stats)
            db_stats
            ;;
        title)
            db_get_title "$2"
            ;;
        migrate)
            db_init
            db_migrate_from_txt "${2:-/app/.yt-dlp-config/history.txt}"
            ;;
        help|*)
            echo "Usage: $0 <command> [args]"
            echo ""
            echo "Commands:"
            echo "  init              Initialize the database"
            echo "  exists <url>      Check if URL exists in history"
            echo "  record <url> [title] [format] [file_path] [file_size] [duration]"
            echo "  fail <url> [title] [format]"
            echo "  info <url>        Get download info"
            echo "  recent [limit]    Show recent downloads"
            echo "  stats             Show download statistics"
            echo "  title <url>       Get title from history"
            echo "  migrate [file]    Migrate from history.txt"
            ;;
    esac
fi
