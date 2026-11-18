#!/bin/bash
set -uo pipefail
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

TMP=$(mktemp -d)
export DB_MODE=local DB_FILE="$TMP/history.db"
export CONFIG_DIR="$TMP/cfg" LOG_DIR="$TMP/log"
export VIDEO_DIR="$TMP/Videos" MUSIC_DIR="$TMP/Music"
export QUEUE_FILE="$CONFIG_DIR/queue.txt"
mkdir -p "$VIDEO_DIR" "$MUSIC_DIR" "$LOG_DIR" "$CONFIG_DIR"
unset DB_URI

# load the real downloader body (function defs only, main block stripped)
sed -e '/^# === Main ===/,$d' -e "s#^SCRIPT_DIR=.*#SCRIPT_DIR=$SRC#" "$SRC/downloader.sh" > "$TMP/body.sh"
source "$TMP/body.sh"

# --- seed DB ---
db_record_success   "https://x.com/ok/status/1"  "ok"   "best" "$TMP/f" 10 0
db_record_failure   "https://x.com/old/status/2" "old"  "best"
db_record_failure   "https://x.com/fresh/status/3" "fresh" "best"
db_record_failure   "https://www.pornhub.com/model/foo" "foo" "best"
sqlite3 "$DB_FILE" "UPDATE downloads SET downloaded_at=datetime('now','localtime','-24 hours') WHERE url LIKE '%/old/%'"

pass=0; fail=0
check() { if eval "$2"; then echo "PASS: $1"; pass=$((pass+1)); else echo "FAIL: $1"; fail=$((fail+1)); fi; }

# --- 1. cooldown filter (real SQL) ---
stale12=$(db_list_stale_failed_urls 12)
stale0=$(db_list_stale_failed_urls 0)
check "cooldown 12h -> only the old failure" "[[ \"\$stale12\" == 'https://x.com/old/status/2' ]]"
check "cooldown 0h  -> old + fresh, no profile" "[[ \$(printf '%s\n' \"\$stale0\" | sort | tr '\n' ',') == 'https://x.com/fresh/status/3,https://x.com/old/status/2,' ]]"

# --- 2. requeue_from_history: cooldown respected, dedupe on repeat ---
RESCAN_PROFILES=true RETRY_FAILED_URLS=true REQUEUE_COOLDOWN_H=12
: > "$QUEUE_FILE"
requeue_from_history
check "requeue adds profile + stale failure" "[[ \$(sort \"\$QUEUE_FILE\" | tr '\n' ',') == 'https://www.pornhub.com/model/foo,https://x.com/old/status/2,' ]]"
requeue_from_history
check "second requeue adds nothing (dedupe)" "[[ \$(wc -l < \"\$QUEUE_FILE\") -eq 2 ]]"

# --- 3. fresh failure is NOT re-queued while inside cooldown ---
grep -qxF "https://x.com/fresh/status/3" "$QUEUE_FILE" && check "fresh failure stays out" "false" || check "fresh failure stays out" "true"
grep -qxF "https://x.com/ok/status/1" "$QUEUE_FILE" && check "success not re-queued" "false" || check "success not re-queued" "true"

# --- 4. interval gate ---
REQUEUE_INTERVAL_H=6
rm -f "$REQUEUE_MARKER"
requeue_due && check "no marker -> requeue due" "true" || check "no marker -> requeue due" "false"
run_requeue >/dev/null 2>&1
requeue_due && check "just ran -> not due" "false" || check "just ran -> not due" "true"
echo $(( $(date +%s) - 7*3600 )) > "$REQUEUE_MARKER"
requeue_due && check "7h old -> due again" "true" || check "7h old -> due again" "false"
REQUEUE_INTERVAL_H=0
requeue_due && check "interval 0 -> always due" "true" || check "interval 0 -> always due" "false"

# --- 5. simple mode must not rebuild from history: eval the real guard line ---
guard=$(grep -o '\[\[ "\$WATCH_MODE" != "simple" \]\] && requeue_due' "$SRC/downloader.sh" | head -1)
[[ -z "$guard" ]] && guard='__missing__'
rm -f "$REQUEUE_MARKER"
WATCH_MODE=simple REQUEUE_INTERVAL_H=6
check "simple: guard false (even with no marker)" "! eval \"$guard\""
WATCH_MODE=full REQUEUE_INTERVAL_H=6
check "full: guard true on start" "eval \"$guard\""

pguard=$(grep -o '\[\[ "\$WATCH_MODE" != "simple" && "\$REQUEUE_INTERVAL_H" -gt 0 \]\] && requeue_due' "$SRC/downloader.sh" | head -1)
[[ -z "$pguard" ]] && pguard='__missing__'
WATCH_MODE=full REQUEUE_INTERVAL_H=0
check "full + interval 0: polling guard off" "! eval \"$pguard\""
WATCH_MODE=full REQUEUE_INTERVAL_H=6
check "full + interval 6: polling guard on" "eval \"$pguard\""

# --- 6. cookie_file_ok: empty/garbage rejected, real Netscape accepted ---
: > "$COOKIES_FILE"
check "empty jar rejected" "! cookie_file_ok \"$COOKIES_FILE\""
printf '\n# Netscape HTTP Cookie File\n' > "$COOKIES_FILE"
check "header-only jar rejected" "! cookie_file_ok \"$COOKIES_FILE\""
: > "$COOKIES_FILE"
printf '\t%s' '.pornhub.com' 'TRUE' '/' 'FALSE' '0' 'il' 'x' >> "$COOKIES_FILE"
check "Netscape jar accepted" "cookie_file_ok \"$COOKIES_FILE\""

# --- 7. purge_zero_partials: 0-byte stubs dropped, real partials kept ---
mkdir -p "$VIDEO_DIR/p"
: > "$VIDEO_DIR/p/dead.mp4.ytdl"
: > "$VIDEO_DIR/p/dead2.mp4.part"
printf 'x' > "$VIDEO_DIR/p/live.mp4.part"
purge_zero_partials >/dev/null 2>&1
check "0-byte stub removed" "[[ ! -e \"$VIDEO_DIR/p/dead.mp4.ytdl\" && ! -e \"$VIDEO_DIR/p/dead2.mp4.part\" ]]"
check "real partial kept" "[[ -s \"$VIDEO_DIR/p/live.mp4.part\" ]]"
rm -f "$COOKIES_FILE"

echo "res=$(grep -c 'Re-queued' "$LOG_FILE" 2>/dev/null || echo 0) log lines"
echo "PASS=$pass FAIL=$fail"
rm -rf "$TMP"
[[ "$fail" -eq 0 ]]
