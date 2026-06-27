#!/bin/bash
# ======================================================
# YouTube Downloader v1.0.0 - entrypoint
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

# === Create user with matching UID/GID ===
if ! getent group "$USER_GID" > /dev/null 2>&1; then
    addgroup -g "$USER_GID" "$USERNAME"
else
    EXISTING_GROUP=$(getent group "$USER_GID" | cut -d: -f1)
    if [ "$EXISTING_GROUP" != "$USERNAME" ]; then
        USERNAME="$EXISTING_GROUP"
    fi
fi

if ! id -u "$USERNAME" > /dev/null 2>&1; then
    adduser -D -u "$USER_UID" -G "$USERNAME" "$USERNAME"
fi

# === Fix permissions on all mounted directories ===
chown -R "$USER_UID:$USER_GID" /app/downloads 2>/dev/null || true
chown -R "$USER_UID:$USER_GID" /app/.yt-dlp-logs 2>/dev/null || true
chown -R "$USER_UID:$USER_GID" /app/.yt-dlp-config 2>/dev/null || true

# === Ensure download directories exist ===
mkdir -p /app/downloads/Videos /app/downloads/Music /app/.yt-dlp-logs /app/.yt-dlp-config
chown -R "$USER_UID:$USER_GID" /app/downloads /app/.yt-dlp-logs /app/.yt-dlp-config

# === Execute main command as the user ===
exec su-exec "$USERNAME" "$@"
