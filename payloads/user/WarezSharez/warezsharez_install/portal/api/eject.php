<?php
// POST eject.php  with  path=<usb mount rel path>  ->  flush buffers to disk so the
// drive can be safely pulled. php-fpm runs as 'nobody' and can't umount, but it can
// sync(); the physical pull then fires the hotplug unmount. This prevents the
// "filename written but no data" loss on vfat when a drive is removed after a write.
require_once __DIR__ . '/_lib.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    warez_fail('POST required', 405);
}

$rel = isset($_POST['path']) ? $_POST['path'] : '';
$dir = warez_resolve($rel, true, 'write');   // must resolve inside the share
if ($dir === false || !is_dir($dir)) {
    warez_fail('Not found', 404);
}

if (function_exists('exec')) { @exec('sync'); }

warez_json(array('ok' => true, 'msg' => 'flushed - safe to remove'));
