#!/bin/bash
# DB-stored settings that config.php can't express. Idempotent, runs on
# every start so a fresh install comes out configured.
set -e

occ() { php /var/www/html/occ "$@"; }

occ background:job:mode cron

# ExApps need a Docker deploy daemon we don't run
if occ app:list --enabled | grep -q -- '- app_api:'; then
    occ app:disable app_api
fi
