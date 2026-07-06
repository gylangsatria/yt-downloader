FROM alpine:3.19

LABEL version="2.0.0" \
      description="YouTube/Twitter Downloader - Automatic Mode" \
      author="gylangsatria" \
      github="https://github.com/gylangsatria"

# Install dependencies
RUN apk add --no-cache \
    python3 \
    py3-pip \
    ffmpeg \
    bash \
    curl \
    su-exec \
    && python3 -m venv /opt/venv \
    && /opt/venv/bin/pip install --no-cache-dir yt-dlp curl_cffi \
    && ln -s /opt/venv/bin/yt-dlp /usr/local/bin/yt-dlp

ENV PATH="/opt/venv/bin:$PATH"

WORKDIR /app

# Copy scripts
COPY entrypoint.sh /entrypoint.sh
COPY downloader.sh /app/downloader.sh
RUN chmod +x /entrypoint.sh /app/downloader.sh

# Default environment variables
ENV USERNAME=appuser
ENV USER_UID=1000
ENV USER_GID=1000
ENV VIDEO_DIR=/app/downloads/Videos
ENV MUSIC_DIR=/app/downloads/Music

ENTRYPOINT ["/entrypoint.sh"]
CMD ["/app/downloader.sh"]