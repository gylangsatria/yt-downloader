#!/bin/bash
# ======================================================
# YouTube Downloader v1.0.0
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
    env UID="$MY_UID" GID="$MY_GID" USER="$MY_USER" docker compose run --rm yt-downloader "$@"
fi