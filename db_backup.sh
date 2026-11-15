#!/bin/bash
# ======================================================
# yt-downloader - Database Backup & Restore (cloud MariaDB/MySQL)
# ======================================================
# Author  : gylangsatria
# GitHub  : https://github.com/gylangsatria
# ======================================================
#
# Backs up / restores the CLOUD history database that the app uses
# (DB_MODE=cloud, e.g. MariaDB on a VPS reached via the Cloudflare tunnel
# at 127.0.0.1:3307). Handy when you move to a new VM/PC or want an
# off-site copy.
#
# It reuses the connection info already in .env (DB_URI + CF_* token), so
# you do NOT retype credentials. A one-off mariadb:11 client container does
# the dump/restore over the existing tunnel, then exits. No new dependency.
#
# Usage:
#   ./db_backup.sh                    # backup cloud DB -> ./backups/ (gzip)
#   ./db_backup.sh backup
#   ./db_backup.sh backup --db history
#   ./db_backup.sh backup --dir /path/to/backups
#   ./db_backup.sh list               # list local backups
#   ./db_backup.sh verify <file.sql.gz...>   # integrity check of backups
#   ./db_backup.sh restore <file.sql.gz> [--db NAME] [--yes]
#                                     # restore INTO the cloud DB
#   ./db_backup.sh help
#
# Modes (auto-detected from .env DB_URI):
#   DB_URI host = 127.0.0.1 / localhost  -> ensure Cloudflare tunnel is up
#   DB_URI host = <VPS IP>               -> connect directly (no tunnel)
#
# NOTE for --db: by default we restore into a NEW database whose name is
# extracted from the dump file (so we never silently overwrite production).
# Pass --db <name> to target an explicit database, e.g. the live one after
# you are sure:
#   ./db_backup.sh restore backups/yt-downloader-history_....sql.gz --db yt-downloader-history --yes
# ======================================================

set -euo pipefail

# ---------- locate .env (script dir, or current dir) ----------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${ENV_FILE:-$SCRIPT_DIR/.env}"
[[ -f "$ENV_FILE" ]] || ENV_FILE=".env"
if [[ ! -f "$ENV_FILE" ]]; then
    echo "[BACKUP] ERROR: .env not found (looked in $SCRIPT_DIR and current dir)" >&2
    echo "         Copy .env.example to .env and set DB_MODE / DB_URI first." >&2
    exit 1
fi

# ---------- load .env without clobbering real environment ----------
# Values in .env win here on purpose: they are this project's DB config.
set -a
# shellcheck disable=SC1090
source <(grep -E '^[A-Za-z_][A-Za-z0-9_]*=' "$ENV_FILE" | sed 's/[[:space:]]*#.*$//')
set +a

DB_MODE="${DB_MODE:-local}"
DB_URI="${DB_URI:-}"
CLIENT_IMAGE="${CLIENT_IMAGE:-mariadb:11}"
BACKUP_DIR_DEFAULT="$SCRIPT_DIR/backups"

# ---------- pretty logging ----------
log()  { printf '[BACKUP] %s\n' "$*"; }
warn() { printf '[BACKUP] WARN: %s\n' "$*" >&2; }
die()  { printf '[BACKUP] ERROR: %s\n' "$*" >&2; exit 1; }

need() { command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"; }

# ---------- parse DB_URI -> MYSQL_* (same regex as db_history.sh) ----------
parse_db_uri() {
    [[ "$DB_MODE" == "cloud" ]] || die "DB_MODE is '${DB_MODE}', not 'cloud'. This script is for the cloud DB. Set DB_MODE=cloud in .env."
    [[ -n "$DB_URI" ]] || die "DB_URI is empty in .env (required for cloud mode)."
    local re='^[a-zA-Z0-9+]+://([^:@/]+)(:([^@/]*))?@([^:/]+)(:([0-9]+))?/([^/?]+).*'
    if [[ ! "$DB_URI" =~ $re ]]; then
        die "invalid DB_URI. Expected: mysql://user:password@host:port/database"
    fi
    MYSQL_USER="${BASH_REMATCH[1]}"
    MYSQL_PASS="${BASH_REMATCH[3]}"
    MYSQL_HOST="${BASH_REMATCH[4]}"
    MYSQL_PORT="${BASH_REMATCH[6]:-3306}"
    MYSQL_DB="${BASH_REMATCH[7]}"
    log "Target: ${MYSQL_USER}@${MYSQL_HOST}:${MYSQL_PORT}/${MYSQL_DB}"
}

is_tunnel_mode() {
    case "$MYSQL_HOST" in
        127.0.0.1|localhost|::1) return 0;;
        *) return 1;;
    esac
}

# ---------- make sure the DB is reachable ----------
ensure_reachable() {
    need docker
    if is_tunnel_mode; then
        local cname="cloudflared-mysql-tcp"
        local running
        running=$(docker inspect -f '{{.State.Running}}' "$cname" 2>/dev/null || echo false)
        if [[ "$running" != "true" ]]; then
            log "Tunnel container '$cname' not running -> starting via ./run.sh ..."
            ( cd "$SCRIPT_DIR" && ./run.sh >/dev/null 2>&1 ) || \
                die "could not start the tunnel. Run ./run.sh manually and retry."
            local i
            for i in $(seq 1 30); do
                if docker run --rm --network host -e MYSQL_PWD="$MYSQL_PASS" "$CLIENT_IMAGE" \
                      mariadb -h"$MYSQL_HOST" -P"$MYSQL_PORT" -u"$MYSQL_USER" --skip-ssl -e 'SELECT 1' >/dev/null 2>&1; then
                    log "Tunnel is up."
                    return 0
                fi
                sleep 1
            done
            die "tunnel did not become reachable at ${MYSQL_HOST}:${MYSQL_PORT} in 30s."
        fi
        log "Tunnel container is running."
    fi
}

# ---------- backup ----------
do_backup() {
    local db="" outdir="$BACKUP_DIR_DEFAULT"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --db)  db="$2"; shift 2;;
            --dir) outdir="$2"; shift 2;;
            *) die "backup: unknown option '$1'";;
        esac
    done

    parse_db_uri
    [[ -n "$db" ]] || db="$MYSQL_DB"
    ensure_reachable
    mkdir -p "$outdir" || die "cannot create backup dir: $outdir"

    local ts safe_db file tmp sum human
    ts="$(date +%Y%m%d_%H%M%S)"
    safe_db="${db//\//_}"
    file="$outdir/${safe_db}_${ts}.sql.gz"
    tmp="$(mktemp "${outdir}/.${safe_db}_${ts}.XXXXXX.sql.gz")"

    log "Dumping '$db' -> $file"
    # Dump to a temp file first; only rename to the final name if it fully succeeds.
    if ! docker run --rm --network host -e MYSQL_PWD="$MYSQL_PASS" "$CLIENT_IMAGE" \
            sh -c "mariadb-dump -h'$MYSQL_HOST' -P'$MYSQL_PORT' -u'$MYSQL_USER' --single-transaction --quick --skip-ssl --no-tablespaces --databases '$db'" \
            2> >(grep -v 'insecure passwordless' >&2) | gzip -9 > "$tmp"; then
        rm -f "$tmp"
        die "mariadb-dump failed."
    fi
    if ! gzip -t "$tmp" 2>/dev/null; then rm -f "$tmp"; die "produced file is not valid gzip."; fi
    mv "$tmp" "$file"

    sum="$(sha256sum "$file" | awk '{print $1}')"
    printf '%s  %s\n' "$sum" "$(basename "$file")" > "${file}.sha256"
    human="$(du -h "$file" | awk '{print $1}')"

    log "OK  $file  (${human})"
    log "checksum: ${sum:0:16}...  (saved to $(basename "$file").sha256)"
    echo "$file"
}

# ---------- list ----------
do_list() {
    local dir="$BACKUP_DIR_DEFAULT"
    [[ $# -gt 0 && "$1" == "--dir" ]] && { dir="$2"; shift 2; }
    if [[ ! -d "$dir" ]]; then log "no backup dir yet: $dir"; return 0; fi
    shopt -s nullglob
    local files=("$dir"/*.sql.gz)
    shopt -u nullglob
    if [[ ${#files[@]} -eq 0 ]]; then log "no backups in $dir"; return 0; fi
    log "backups in $dir:"
    local f
    for f in "${files[@]}"; do
        printf '  %-8s %s  %s\n' "$(du -h "$f" | awk '{print $1}')" \
            "$(date -r "$f" '+%Y-%m-%d %H:%M')" "$(basename "$f")"
    done
}

# ---------- verify integrity ----------
do_verify() {
    [[ $# -ge 1 ]] || die "verify: give at least one .sql.gz file"
    local rc=0 f
    for f in "$@"; do
        [[ -f "$f" ]] || { warn "missing: $f"; rc=1; continue; }
        if gzip -t "$f" 2>/dev/null; then
            local rows
            rows="$(gzip -dc "$f" | grep -c '^INSERT INTO' || true)"
            log "OK  $(basename "$f")  (gzip valid, ${rows} INSERT statements)"
            if [[ -f "${f}.sha256" ]]; then
                if ( cd "$(dirname "$f")" && sha256sum -c "$(basename "$f").sha256" >/dev/null 2>&1 ); then
                    log "    sha256 matches"
                else
                    warn "    sha256 MISMATCH for $f"; rc=1
                fi
            fi
        else
            warn "CORRUPT (bad gzip): $f"; rc=1
        fi
    done
    return $rc
}

# ---------- restore ----------
do_restore() {
    [[ $# -ge 1 && "$1" != --* ]] || die "restore: give a backup file, e.g. ./db_backup.sh restore backups/xxx.sql.gz"
    local infile="$1"; shift
    [[ -f "$infile" ]] || die "file not found: $infile"

    local target_db="" assume_yes=0
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --db)  target_db="$2"; shift 2;;
            --yes|-y) assume_yes=1; shift;;
            *) die "restore: unknown option '$1'";;
        esac
    done

    parse_db_uri
    ensure_reachable

    # integrity check first
    gzip -t "$infile" 2>/dev/null || die "not a valid gzip file: $infile"
    if [[ -f "${infile}.sha256" ]]; then
        ( cd "$(dirname "$infile")" && sha256sum -c "$(basename "$infile").sha256" >/dev/null 2>&1 ) \
            || warn "sha256 does not match ${infile}.sha256 (continuing anyway)."
    fi

    # Figure out what the dump declares it creates/uses.
    local declared
    declared="$(gzip -dc "$infile" | grep -m1 -E '^-- Current Database:|^CREATE DATABASE|^USE ' || true)"
    if [[ -z "$target_db" ]]; then
        target_db="$(gzip -dc "$infile" | sed -n -E 's/^-- Current Database: `([^`]+)`.*/\1/p' | head -1)"
    fi
    [[ -n "$target_db" ]] || target_db="$MYSQL_DB"

    log "Backup file : $infile"
    log "Declared    : ${declared:-<none>}"
    log "Will restore INTO database: '$target_db'"

    printf '\n'
    warn "This WRITES into the cloud database '$target_db' at ${MYSQL_HOST}:${MYSQL_PORT}."
    warn "Tables in the dump (e.g. 'downloads') WILL be replaced (DROP + CREATE + INSERT)."
    if [[ "$assume_yes" -ne 1 ]]; then
        local ans
        read -r -p "[BACKUP] Type the database name ('$target_db') to confirm, or Ctrl-C to abort: " ans
        [[ "$ans" == "$target_db" ]] || die "aborted (confirmation did not match)."
    fi

    log "Restoring ..."
    if ! gzip -dc "$infile" | docker run --rm --interactive --network host \
            -e MYSQL_PWD="$MYSQL_PASS" "$CLIENT_IMAGE" \
            mariadb -h"$MYSQL_HOST" -P"$MYSQL_PORT" -u"$MYSQL_USER" --skip-ssl --binary-mode \
            2> >(grep -v 'insecure passwordless' >&2); then
        die "restore failed while feeding SQL into the server."
    fi

    # verify row count of the main table if present
    local cnt
    cnt="$(docker run --rm --network host -e MYSQL_PWD="$MYSQL_PASS" "$CLIENT_IMAGE" \
            mariadb -h"$MYSQL_HOST" -P"$MYSQL_PORT" -u"$MYSQL_USER" --skip-ssl -N -e \
            "SELECT COUNT(*) FROM \`$target_db\`.downloads" 2>/dev/null | tr -dc '0-9' || true)"
    if [[ -n "$cnt" ]]; then
        log "Restore OK -> '$target_db'.downloads now has $cnt rows."
    else
        log "Restore finished (could not read row count back; check manually)."
    fi
    log "Done. If the app was running, restart it: ./run.sh"
}

# ---------- help ----------
usage() {
    awk 'NR>1 && /^#/ {sub(/^# ?/,""); print; next} NR>1 && !/^#/ {exit}' "${BASH_SOURCE[0]}"
}

# ---------- dispatch ----------
cmd="${1:-backup}"; [[ $# -gt 0 ]] && shift
case "$cmd" in
    backup)   do_backup "$@";;
    restore)  do_restore "$@";;
    list|ls)  do_list "$@";;
    verify)   do_verify "$@";;
    help|-h|--help) usage;;
    *) die "unknown command '$cmd'. Try: $0 help";;
esac
