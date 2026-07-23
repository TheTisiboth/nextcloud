<?php
// Merged automatically by Nextcloud on top of config.php. Every value
// here is optional and only applied if its env var is set/non-empty --
// safe to leave blank for a plain LAN/IP setup with no reverse proxy.
$CONFIG = [];

if ($value = getenv('OVERWRITEPROTOCOL')) {
    $CONFIG['overwriteprotocol'] = $value;
}

if ($value = getenv('OVERWRITECLIURL')) {
    $CONFIG['overwrite.cli.url'] = $value;
}

if ($value = getenv('OVERWRITEHOST')) {
    $CONFIG['overwritehost'] = $value;
}

if ($value = getenv('TRUSTED_PROXIES')) {
    $CONFIG['trusted_proxies'] = array_values(array_filter(explode(' ', $value)));
}
