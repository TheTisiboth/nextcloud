<?php
// Merged automatically by Nextcloud on top of config.php (it loads every
// config/*.config.php file alphabetically). No secrets stored here --
// values are pulled from the container's environment at runtime.
$CONFIG = [
    'memcache.local'      => '\OC\Memcache\Redis',
    'memcache.locking'    => '\OC\Memcache\Redis',
    'filelocking.enabled' => true,
    'redis' => [
        'host'     => getenv('REDIS_HOST') ?: 'redis',
        'port'     => (int) (getenv('REDIS_PORT') ?: 6379),
        'password' => getenv('REDIS_PASSWORD') ?: '',
        'timeout'  => 1.5,
    ],
];
