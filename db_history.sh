#!/bin/bash
# ======================================================
# Download History Module - SQLite (local) / MySQL (cloud)
# ======================================================
# Author  : gylangsatria
# GitHub  : https://github.com/gylangsatria
# ======================================================
#
# Tracks download history. Supports two backends:
#   DB_MODE=local  -> SQLite file (default, single PC)
#   DB_MODE=cloud  -> shared MySQL/MariaDB server, so history syncs
#                      between all PCs pointed at the same DB_URI.
#
# Schema (downloads table) exists in both backends.
#
# Environment variables (from .env via docker-compose):
#   DB_MODE - "local" (default) | "cloud"
#   DB_FILE - path to SQLite file (local mode) default /app/.yt-dlp-config/history.db
#   DB_URI  - mysql://user:password@host:port/database (required when DB_MODE=cloud)
# ======================================================

DB_MODE="${DB_MODE:-local}"
DB_FILE="${DB_FILE:-/app/.yt-dlp-config/history.db}"
DB_URI="${DB_URI:-}"

# --- MySQL connection parsing (cloud mode only) ---
MYSQL_HOST=""
MYSQL_PORT="3306"
MYSQL_USER=""
MYSQL_PASS=""
MYSQL_DB=""
MYSQL_ARGS=()
MYSQL_OK=0

db_configure_cloud() {
    local re='^[a-zA-Z0-9+]+://([^:@/]+)(:([^@/]*))?@([^:/]+)(:([0-9]+))?/([^/?]+).*'
    if [[ ! "$DB_URI" =~ $re ]]; then
        echo "[DB] ERROR: invalid DB_URI" >&2
        echo "     Expected: mysql://user:password@host:port/database" >&2
        return 1
    fi
    MYSQL_USER="${BASH_REMATCH[1]}"
    MYSQL_PASS="${BASH_REMATCH[3]}"
    MYSQL_HOST="${BASH_REMATCH[4]}"
    MYSQL_PORT="${BASH_REMATCH[6]:-3306}"
    MYSQL_DB="${BASH_REMATCH[7]}"
    MYSQL_ARGS=(--default-character-set=utf8mb4 -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER")
    [[ -n "$MYSQL_PASS" ]] && MYSQL_ARGS+=("-p$MYSQL_PASS")
    MYSQL_ARGS+=("$MYSQL_DB")
}

# Backend-specific SQL fragments
DB_NOW="datetime('now','localtime')"
DB_UPSERT="INSERT OR REPLACE INTO"
DB_INSERT_IGNORE="INSERT OR IGNORE INTO"
DB_STATS_TODAY="date(downloaded_at) = date('now','localtime')"

if [[ "$DB_MODE" == "cloud" ]]; then
    db_configure_cloud && MYSQL_OK=1
    DB_NOW="NOW()"
    DB_UPSERT="REPLACE INTO"
    DB_INSERT_IGNORE="INSERT IGNORE INTO"
    DB_STATS_TODAY="DATE(downloaded_at) = CURDATE()"
fi

# === Execute SQL against the active backend (SQL fed via stdin) ===
# Local : rows '|'-separated. Cloud : rows tab-separated (see *_pipe helpers).
db_exec() {
    if [[ "$DB_MODE" == "cloud" ]]; then
        if [[ "$MYSQL_OK" -ne 1 ]]; then
            echo "[DB] ERROR: cloud DB not configured (check DB_URI in .env)" >&2
            return 1
        fi
        mysql "${MYSQL_ARGS[@]}" --batch --skip-column-names -e "$(cat)"
    else
        printf '%s\n' "$(cat)" | sqlite3 "$DB_FILE"
    fi
}

# === Initialize database ===
db_init() {
    if [[ "$DB_MODE" == "cloud" ]]; then
        if [[ "$MYSQL_OK" -ne 1 ]]; then
            echo "[DB] ERROR: cannot init cloud DB (check DB_URI in .env)" >&2
            return 1
        fi
        mysql "${MYSQL_ARGS[@]}" <<'SQL'
CREATE TABLE IF NOT EXISTS downloads (
    id            INT NOT NULL AUTO_INCREMENT,
    url           VARCHAR(512) NOT NULL,
    title         VARCHAR(512),
    format        VARCHAR(64),
    status        VARCHAR(16)  NOT NULL DEFAULT 'success',
    file_path     VARCHAR(512),
    file_size     BIGINT       NOT NULL DEFAULT 0,
    duration      INT          NOT NULL DEFAULT 0,
    downloaded_at DATETIME     DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_downloads_url (url)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
SQL
        # Best-effort indexes (skip if they already exist)
        for col in status downloaded_at; do
            mysql "${MYSQL_ARGS[@]}" -e "CREATE INDEX idx_downloads_${col} ON downloads(${col});" 2>/dev/null || true
        done
    else
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
    fi
}

# === Check if URL already exists in database ===
# Returns 0 (true) if exists, 1 (false) if not
db_url_exists() {
    local url="$1"
    local count
    count=$(db_exec <<< "SELECT COUNT(*) FROM downloads WHERE url = '$(sqlite3_escape "$url")'")
    [[ "$count" -gt 0 ]]
}

# === Sanitize numeric value (force to integer, default 0) ===
sanitize_num() {
    local val="$1"
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

    db_exec <<SQL
$DB_UPSERT downloads (url, title, format, status, file_path, file_size, duration, downloaded_at)
VALUES (
    '$(sqlite3_escape "$url")',
    '$(sqlite3_escape "$title")',
    '$(sqlite3_escape "$format")',
    'success',
    '$(sqlite3_escape "$file_path")',
    $file_size,
    $duration,
    $DB_NOW
);
SQL
}

# === Record a failed download attempt ===
db_record_failure() {
    local url="$1"
    local title="$2"
    local format="$3"

    db_exec <<SQL
$DB_UPSERT downloads (url, title, format, status, downloaded_at)
VALUES (
    '$(sqlite3_escape "$url")',
    '$(sqlite3_escape "$title")',
    '$(sqlite3_escape "$format")',
    'failed',
    $DB_NOW
);
SQL
}

# === Get download info for a URL ===
# Prints: title|format|status|file_path|downloaded_at
db_get_info() {
    local url="$1"
    db_exec <<SQL | tr '\t' '|'
SELECT title, format, status, file_path, downloaded_at FROM downloads WHERE url = '$(sqlite3_escape "$url")';
SQL
}

# === List recent downloads ===
db_list_recent() {
    local limit="${1:-20}"
    if [[ "$DB_MODE" == "cloud" ]]; then
        echo "id | url | title | status | downloaded_at"
        db_exec <<SQL | sed 's/\t/ | /g'
SELECT id, url, title, status, downloaded_at FROM downloads ORDER BY downloaded_at DESC LIMIT $limit;
SQL
    else
        sqlite3 "$DB_FILE" "SELECT id, url, title, status, downloaded_at FROM downloads ORDER BY downloaded_at DESC LIMIT $limit" -separator ' | ' -header
    fi
}

# === Show download statistics ===
db_stats() {
    if [[ "$DB_MODE" == "cloud" ]]; then
        echo "metric|value"
        db_exec <<SQL | tr '\t' '|'
SELECT 'total',   COUNT(*) FROM downloads
UNION ALL SELECT 'success', COUNT(*) FROM downloads WHERE status = 'success'
UNION ALL SELECT 'failed',  COUNT(*) FROM downloads WHERE status = 'failed'
UNION ALL SELECT 'unique',  COUNT(DISTINCT url) FROM downloads
UNION ALL SELECT 'today',   COUNT(*) FROM downloads WHERE $DB_STATS_TODAY;
SQL
    else
        db_exec <<'SQL'
SELECT 'total'   AS metric, COUNT(*)               AS value FROM downloads
UNION ALL
SELECT 'success' AS metric, COUNT(*)               AS value FROM downloads WHERE status = 'success'
UNION ALL
SELECT 'failed'  AS metric, COUNT(*)               AS value FROM downloads WHERE status = 'failed'
UNION ALL
SELECT 'unique'  AS metric, COUNT(DISTINCT url)    AS value FROM downloads
UNION ALL
SELECT 'today'   AS metric, COUNT(*)               AS value FROM downloads WHERE date(downloaded_at) = date('now','localtime');
SQL
    fi
}

# === Get the title from history if previously downloaded ===
db_get_title() {
    local url="$1"
    db_exec <<< "SELECT title FROM downloads WHERE url = '$(sqlite3_escape "$url")' AND title != '' ORDER BY downloaded_at DESC LIMIT 1"
}

# === Escape single quotes (works for both SQLite and MySQL) ===
sqlite3_escape() {
    local str="$1"
    str="${str//\'/\'\'}"
    echo "$str"
}

# === Migrate from old history.txt into the active backend ===
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
        if [[ "$line" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]][0-9]{2}:[0-9]{2}:[0-9]{2})\ \|\ (https?://[^ ]+)\ \|\ ([^|]+)\ \|\ (.*)$ ]]; then
            date_time="${BASH_REMATCH[1]}"
            url="${BASH_REMATCH[2]}"
            format="$(echo "${BASH_REMATCH[3]}" | xargs)"
            title="$(echo "${BASH_REMATCH[4]}" | xargs)"

            db_exec <<SQL 2>/dev/null
$DB_INSERT_IGNORE downloads (url, title, format, status, downloaded_at)
VALUES ('$(sqlite3_escape "$url")', '$(sqlite3_escape "$title")', '$(sqlite3_escape "$format")', 'success', '$(sqlite3_escape "$date_time")');
SQL
            ((migrated++))
        fi
    done < "$history_file"

    echo "[DB] Migrated $migrated entries from history.txt to database"
}

# === Migrate existing local SQLite history -> cloud MySQL ===
# Usage: DB_MODE=cloud ... db_history.sh migrate-cloud [/path/to/local/history.db]
db_migrate_to_cloud() {
    local src="${1:-/app/.yt-dlp-config/history.db}"

    if [[ "$DB_MODE" != "cloud" ]]; then
        echo "[DB] Set DB_MODE=cloud in .env first." >&2
        return 1
    fi
    if [[ "$MYSQL_OK" -ne 1 ]]; then
        echo "[DB] Cloud DB not configured (check DB_URI)." >&2
        return 1
    fi
    if [[ ! -f "$src" ]]; then
        echo "[DB] No local SQLite file at $src to migrate." >&2
        return 1
    fi
    if ! command -v sqlite3 >/dev/null 2>&1; then
        echo "[DB] ERROR: sqlite3 not found (required to read local DB)." >&2
        return 1
    fi

    # One-shot migration: generate INSERT statements with sqlite3 quote() (proper
    # SQL escaping, incl. quotes/newlines/emoji), cap columns to cloud widths, then
    # stream into a single mysql connection. REPLACE keeps it idempotent by url.
    # ponytail: SUBSTR caps avoid MySQL 1406 (data too long); upgrade = widen columns.
    local sqlfile
    sqlfile=$(mktemp)
    sqlite3 "$src" "
SELECT 'REPLACE INTO downloads (url,title,format,status,file_path,file_size,duration,downloaded_at) VALUES ('||
       quote(SUBSTR(url,1,512))||','||
       COALESCE(quote(SUBSTR(title,1,512)),'NULL')||','||
       COALESCE(quote(SUBSTR(format,1,64)),'NULL')||','||
       COALESCE(quote(SUBSTR(status,1,16)),'NULL')||','||
       COALESCE(quote(SUBSTR(file_path,1,512)),'NULL')||','||
       COALESCE(quote(file_size),'0')||','||
       COALESCE(quote(duration),'0')||','||
       COALESCE(quote(downloaded_at),'NULL')||');'
FROM downloads;" > "$sqlfile"

    local n
    n=$(sqlite3 "$src" "SELECT COUNT(*) FROM downloads;" 2>/dev/null)
    n="${n:-0}"

    if [[ "$n" -eq 0 ]]; then
        echo "[DB] No rows to migrate in $src." >&2
        rm -f "$sqlfile"
        return 0
    fi

    mysql "${MYSQL_ARGS[@]}" < "$sqlfile"
    local rc=$?
    rm -f "$sqlfile"
    if [[ "$rc" -ne 0 ]]; then
        echo "[DB] ERROR: cloud migration failed (mysql exit $rc)." >&2
        return $rc
    fi

    echo "[DB] Migrated $n rows from $src to cloud ($MYSQL_DB@$MYSQL_HOST)."
    echo "[DB] Migrated $n rows from $src to cloud ($MYSQL_DB@$MYSQL_HOST)."
}

# === Migrate existing cloud MySQL -> local SQLite ===
# Usage: DB_MODE=cloud ... db_history.sh migrate-local [/path/to/dest.history.db]
db_migrate_to_local() {
    local dest="${1:-$DB_FILE}"

    if [[ "$DB_MODE" != "cloud" ]]; then
        echo "[DB] Set DB_MODE=cloud in .env first (cloud is the source)." >&2
        return 1
    fi
    if [[ "$MYSQL_OK" -ne 1 ]]; then
        echo "[DB] Cloud DB not configured (check DB_URI)." >&2
        return 1
    fi
    if ! command -v sqlite3 >/dev/null 2>&1; then
        echo "[DB] ERROR: sqlite3 not found (required to write local DB)." >&2
        return 1
    fi

    # Ensure local destination table exists.
    sqlite3 "$dest" <<'SQL'
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
SQL

    # One-shot: dump cloud as tab-separated (IFNULL avoids literal 'NULL'), then
    # .import into a staging table and INSERT OR REPLACE (keyed by url) into local.
    # Staging avoids SQL escaping mismatches (MySQL vs SQLite quote handling).
    # ponytail: raw dump breaks if a field truly contains tab/newline; upgrade =
    #           robust CSV/escaper if such content ever shows up.
    local tmp
    tmp=$(mktemp)
    mysql "${MYSQL_ARGS[@]}" --batch --raw --skip-column-names -e "
SELECT IFNULL(url,''),IFNULL(title,''),IFNULL(format,''),IFNULL(status,''),
       IFNULL(file_path,''),IFNULL(file_size,0),IFNULL(duration,0),IFNULL(downloaded_at,'')
FROM downloads ORDER BY id;" > "$tmp"
    local rc=$?
    if [[ "$rc" -ne 0 ]]; then
        echo "[DB] ERROR: cloud->local migration failed (mysql exit $rc)." >&2
        rm -f "$tmp"
        return $rc
    fi

    sqlite3 "$dest" <<SQL
DROP TABLE IF EXISTS _migrate_import;
CREATE TABLE _migrate_import(url TEXT,title TEXT,format TEXT,status TEXT,file_path TEXT,file_size TEXT,duration TEXT,downloaded_at TEXT);
.mode tabs
.import "$tmp" _migrate_import
INSERT OR REPLACE INTO downloads(url,title,format,status,file_path,file_size,duration,downloaded_at)
  SELECT url,title,format,status,file_path,
         CASE WHEN trim(file_size)='' THEN 0 ELSE CAST(file_size AS INTEGER) END,
         CASE WHEN trim(duration)='' THEN 0 ELSE CAST(duration AS INTEGER) END,
         downloaded_at
  FROM _migrate_import;
DROP TABLE _migrate_import;
SQL
    rc=$?
    rm -f "$tmp"
    if [[ "$rc" -ne 0 ]]; then
        echo "[DB] ERROR: cloud->local migration failed (sqlite exit $rc)." >&2
        return $rc
    fi

    echo "[DB] Migrated cloud ($MYSQL_DB@$MYSQL_HOST) to local $dest."
}

# === Main: run if executed directly ===
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-help}" in
        init)
            db_init
            echo "[DB] Database initialized (mode=$DB_MODE): ${DB_FILE:-$DB_URI}"
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
        migrate-cloud)
            db_init
            db_migrate_to_cloud "${2:-/app/.yt-dlp-config/history.db}"
            ;;
        migrate-local)
            db_migrate_to_local "${2:-}"
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
            echo "  migrate-cloud [sqlite.db]  Push local history to cloud DB"
            echo "  migrate-local [sqlite.db]  Pull cloud DB into local history"
            echo ""
            echo "Backend is chosen by DB_MODE (.env): local (SQLite) | cloud (MySQL)."
            ;;
    esac
fi
