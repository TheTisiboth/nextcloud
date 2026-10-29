#!/bin/bash
# DB-stored settings that config.php can't express. Idempotent, runs on
# every start so a fresh install comes out configured.
set -e

occ() { php /var/www/html/occ "$@"; }

occ background:cron

# ExApps need a Docker deploy daemon we don't run
if occ app:list --enabled | grep -q -- '- app_api:'; then
    occ app:disable app_api
fi

# Thumbnails are generated ahead of time by the cron service
# (cron/www-data runs preview:pre-generate) instead of on each request.
# The app store may be unreachable at boot: don't block startup on it.
if ! occ app:list --enabled | grep -q -- '- previewgenerator:'; then
    occ app:install previewgenerator || occ app:enable previewgenerator \
        || echo "previewgenerator not installed, retrying next start"
fi
# Sizes the Files grid (128) and Photos/Memories (256) request
occ config:app:set previewgenerator squareSizes --value="64 128 256"
occ config:app:set previewgenerator widthSizes --value="256 384"
occ config:app:set previewgenerator heightSizes --value="256"
occ config:app:set preview jpeg_quality --value=60
