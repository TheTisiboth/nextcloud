<?php
// Merged automatically by Nextcloud on top of config.php. Opening a folder
// full of photos/videos fires one preview request per file, each spawning
// an image decode or ffmpeg. With the defaults (4 new / 8 total at once on
// the Pi's 4 cores, 4096px previews) that took Nextcloud from 400 MiB to
// 2.7 GiB in 30s and froze the Pi until the watchdog rebooted it.
$CONFIG = [
    'preview_concurrency_new' => 2,
    'preview_concurrency_all' => 4,
    'preview_max_x'           => 2048,
    'preview_max_y'           => 2048,
];
