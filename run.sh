#!/bin/bash
# ======================================================
# YouTube/Twitter Downloader v3.0.0
# Auto-detect UID/GID and run
# ======================================================
# Author  : gylangsatria
# GitHub  : https://github.com/gylangsatria
# ======================================================

set -e

MY_UID=$(id -u)
MY_GID=$(id -g)
MY_USER=$(whoami)

echo "=============================================="
echo "  YouTube Downloader - Automatic Mode"
echo "=============================================="
echo "  User : $MY_USER"
echo "  UID  : $MY_UID"
echo "  GID  : $MY_GID"
echo "=============================================="
echo ""

# Check if image needs building
if ! docker image inspect yt-downloader:latest > /dev/null 2>&1; then
    echo "[BUILD] Building Docker image..."
    docker compose build
    echo ""
fi

# Start the container with UID/GID passed as environment variables
echo "[START] Starting container..."

# --- DB tunnel handling (driven by .env DB_URI, no hostnames here) ---
NEEDS_TUNNEL=0
if [[ -f .env ]]; then
    DB_URI="$(sed -n 's/^DB_URI=//p' .env | tail -1)"
    case "$DB_URI" in
        *127.0.0.1*|*localhost*) NEEDS_TUNNEL=1;;
    esac
fi
if [[ "$NEEDS_TUNNEL" -eq 1 ]]; then
    echo "[TUNNEL] DB_URI uses 127.0.0.1 -> starting cloudflared tunnel..."
    env UID="$MY_UID" GID="$MY_GID" USER="$MY_USER" docker compose up -d cloudflared-mysql-tcp
else
    docker compose rm -sf cloudflared-mysql-tcp >/dev/null 2>&1 || true
fi

env UID="$MY_UID" GID="$MY_GID" USER="$MY_USER" docker compose up -d
echo ""
echo "[DONE] Container is running!"
echo ""
echo "  Add URLs to: data/config/queue.txt"
echo "  Downloads  : downloads/Videos/  or  downloads/Music/"
echo "  Logs       : data/logs/"
echo ""
echo "  Or download directly:"
echo "    ./run.sh \"https://youtube.com/watch?v=...\""
echo ""

# If URL arguments provided, run download and exit
if [[ $# -gt 0 ]]; then
    echo "[RUN] Downloading $# URL(s)..."
    env UID="$MY_UID" GID="$MY_GID" USER="$MY_USER" docker compose run --rm yt-downloader /app/downloader.sh "$@"
fi