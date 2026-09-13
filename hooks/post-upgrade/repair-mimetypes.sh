#!/bin/bash
# Upgrades can ship MIME-type migrations that `occ upgrade` skips as too
# expensive; run them right after each upgrade instead.
set -e

php /var/www/html/occ maintenance:repair --include-expensive
