#!/bin/bash
# Runs after Nextcloud's own install/upgrade init has finished setting up
# /var/www/html/config (see entrypoint.sh's "before-starting" hook stage).
# Our config snippets are bind-mounted read-only at /custom-config instead
# of directly into config/, because a bind mount occupying a path inside
# config/ before that init step runs breaks its ability to write the
# directory at all -- copying in afterwards avoids that entirely.
set -e

cp /custom-config/redis.config.php /var/www/html/config/redis.config.php
cp /custom-config/proxy.config.php /var/www/html/config/proxy.config.php

chown www-data:www-data /var/www/html/config/redis.config.php /var/www/html/config/proxy.config.php
chmod 640 /var/www/html/config/redis.config.php /var/www/html/config/proxy.config.php
