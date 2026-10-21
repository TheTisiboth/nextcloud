<?php
// Merged automatically by Nextcloud on top of config.php. Setting this
// list replaces Nextcloud's default one, so the defaults are repeated
// here; Movie is the addition (video thumbnails, needs ffmpeg -- see
// Dockerfile).
$CONFIG = [
    'enabledPreviewProviders' => [
        'OC\Preview\PNG',
        'OC\Preview\JPEG',
        'OC\Preview\GIF',
        'OC\Preview\BMP',
        'OC\Preview\XBitmap',
        'OC\Preview\Krita',
        'OC\Preview\WebP',
        'OC\Preview\MarkDown',
        'OC\Preview\TXT',
        'OC\Preview\OpenDocument',
        'OC\Preview\Movie',
    ],
];
