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
    gcompat \
    fontconfig \
    freetype \
    libstdc++ \
    && python3 -m venv /opt/venv \
    && /opt/venv/bin/pip install --no-cache-dir yt-dlp curl_cffi \
    && ln -s /opt/venv/bin/yt-dlp /usr/local/bin/yt-dlp

# PhantomJS: yt-dlp's PornHub extractor needs it to solve the site's JS challenge
# page (RNKEY / onload="go()"). Without it most profile videos error out and are
# never downloaded. Not packaged for Alpine 3.19, so use the static build + gcompat.
RUN curl -fsSL -o /tmp/phantomjs.tar.bz2 \
        https://bitbucket.org/ariya/phantomjs/downloads/phantomjs-2.1.1-linux-x86_64.tar.bz2 \
    && tar xjf /tmp/phantomjs.tar.bz2 -C /opt \
    && mv /opt/phantomjs-2.1.1-linux-x86_64 /opt/phantomjs \
    && rm /tmp/phantomjs.tar.bz2 \
    # 2.1.1 predates OpenSSL 3; Alpine's openssl.cnf makes it abort
    && printf '#!/bin/sh\nOPENSSL_CONF=/dev/null exec /opt/phantomjs/bin/phantomjs "$@"\n' > /usr/local/bin/phantomjs \
    && chmod +x /usr/local/bin/phantomjs \
    && phantomjs --version

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