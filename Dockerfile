FROM alpine:3.19

LABEL version="3.0.0" \
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
    sqlite \
    mariadb-client \
    inotify-tools \
    findutils \
    && python3 -m venv /opt/venv \
    && /opt/venv/bin/pip install --no-cache-dir yt-dlp curl_cffi \
    && ln -s /opt/venv/bin/yt-dlp /usr/local/bin/yt-dlp

# PhantomJS is deliberately NOT installed: yt-dlp's PornHub extractor uses it to
# solve the site's JS challenge page, but 2.1.1 hangs on modern TLS inside this
# image (it stalls even on http://example.com). The downloader instead retries the
# URL (MAX_ATTEMPTS in .env) - the challenge is intermittent, so a retry gets in.

ENV PATH="/opt/venv/bin:$PATH"

WORKDIR /app

# Copy scripts
COPY entrypoint.sh /entrypoint.sh
COPY downloader.sh /app/downloader.sh
COPY db_history.sh /app/db_history.sh
RUN chmod +x /entrypoint.sh /app/downloader.sh /app/db_history.sh

# Default environment variables
ENV USERNAME=appuser
ENV USER_UID=1000
ENV USER_GID=1000
ENV VIDEO_DIR=/app/downloads/Videos
ENV MUSIC_DIR=/app/downloads/Music

ENTRYPOINT ["/entrypoint.sh"]
CMD ["/app/downloader.sh"]