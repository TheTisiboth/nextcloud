# Official image + ffmpeg, which it doesn't ship. Nextcloud's Movie preview
# provider needs it for video thumbnails, and Memories for video metadata
# and playback (it finds ffmpeg/ffprobe on PATH by itself).
ARG NEXTCLOUD_IMAGE_TAG
FROM nextcloud:${NEXTCLOUD_IMAGE_TAG}

RUN apt-get update \
    && apt-get install -y --no-install-recommends ffmpeg \
    && rm -rf /var/lib/apt/lists/*
