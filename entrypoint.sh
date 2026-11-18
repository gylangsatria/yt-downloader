#!/bin/bash
# ======================================================
# YouTube/Twitter Downloader v3.0.0 - entrypoint
# Auto-create user & fix permissions at runtime
# ======================================================
# Author  : gylangsatria
# GitHub  : https://github.com/gylangsatria
# ======================================================

set -e

# === Auto-detect or use environment variables ===
USERNAME="${USERNAME:-appuser}"
USER_UID="${USER_UID:-1000}"
USER_GID="${USER_GID:-1000}"

# === Create group with matching GID ===
if ! getent group "$USER_GID" > /dev/null 2>&1; then
    addgroup -g "$USER_GID" "$USERNAME"
fi

# Create user with matching UID
# NOTE: busybox `id -u <numeric>` fails ("unknown user 1000"), so look the UID up in /etc/passwd
if ! getent passwd "$USER_UID" > /dev/null 2>&1; then
    if getent group "$USER_GID" > /dev/null 2>&1; then
        # Group exists, create user with that existing group
        EXISTING_GROUP_NAME=$(getent group "$USER_GID" | cut -d: -f1)
        adduser -D -u "$USER_UID" -G "$EXISTING_GROUP_NAME" "$USERNAME"
    else
        # Group and user both new
        adduser -D -u "$USER_UID" -G "$USERNAME" "$USERNAME"
    fi
fi
# Re-evaluate username from UID in case it was created with a different group name
USERNAME=$(getent passwd "$USER_UID" | cut -d: -f1 || echo "$USERNAME")

# === Fix permissions on all mounted directories ===
chown -R "$USER_UID:$USER_GID" /app/downloads 2>/dev/null || true
chown -R "$USER_UID:$USER_GID" /app/.yt-dlp-logs 2>/dev/null || true
# Chown config items excluding read-only mounted cookies.txt
find /app/.yt-dlp-config -mindepth 1 -maxdepth 1 ! -name 'cookies.txt' -exec chown -R "$USER_UID:$USER_GID" {} + 2>/dev/null || true

# === Ensure download directories exist ===
mkdir -p /app/downloads/Videos /app/downloads/Music /app/.yt-dlp-logs /app/.yt-dlp-config
chown -R "$USER_UID:$USER_GID" /app/downloads /app/.yt-dlp-logs 2>/dev/null || true
chown "$USER_UID:$USER_GID" /app/.yt-dlp-config 2>/dev/null || true
find /app/.yt-dlp-config -mindepth 1 -maxdepth 1 ! -name 'cookies.txt' -exec chown -R "$USER_UID:$USER_GID" {} + 2>/dev/null || true

# yt-dlp aborts every download when handed an empty/garbage cookie jar, so drop it
if [[ -f /app/.yt-dlp-config/cookies.txt ]] && ! awk -F'\t' '/^[^#]/ && NF >= 7 { found=1; exit } END { exit !found }' /app/.yt-dlp-config/cookies.txt 2>/dev/null; then
    rm -f /app/.yt-dlp-config/cookies.txt
fi

# === If first arg is a URL (not a script), prepend downloader ===
if [[ "$1" == http* ]] || [[ "$1" == *youtube* ]] || [[ "$1" == *youtu.be* ]] || [[ "$1" == *twitter.com* ]] || [[ "$1" == *x.com* ]]; then
    exec su-exec "$USERNAME" /app/downloader.sh "$@"
fi

# === Execute main command as the user ===
exec su-exec "$USERNAME" "$@"
