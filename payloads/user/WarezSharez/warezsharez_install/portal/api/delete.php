<?php
// POST delete.php  with  path=<relative dir>&name=<entry>  ->  deletes a file (or empty dir).
require_once __DIR__ . '/_lib.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    warez_fail('POST required', 405);
}
if (!warez_allow_delete()) {
    warez_fail('Deletes are disabled', 403);
}

$rel  = isset($_POST['path']) ? $_POST['path'] : '';
$name = isset($_POST['name']) ? warez_safe_name($_POST['name']) : '';
if ($name === '') { warez_fail('No name given'); }

$target = warez_resolve(($rel === '' ? '' : $rel . '/') . $name, true, 'read');
if ($target === false || !file_exists($target)) {
    warez_fail('Not found', 404);
}

// Deletes are confined to the share (write root), even though reads roam wider.
// The share includes USB drives (mounted under warezsharez/usb/), so those are deletable;
// sibling folders under /mmc/root are not.
if (!warez_within($target, warez_write_root())) {
    warez_fail('Deletes are only allowed inside the WarezSharez folder', 403);
}

// Never delete the share root itself (e.g. a "..#/name=<root>" recombination that
// resolves back onto the root while staying technically "contained").
if ($target === warez_write_root()) {
    warez_fail('Refusing to delete the share root', 403);
}

// Never delete a mountpoint itself (the USB drive's mount dir); files on it are fine.
if (is_dir($target) && warez_is_mount($target)) {
    warez_fail('Refusing to delete a mounted drive', 403);
}

$ok = is_dir($target) ? @rmdir($target) : @unlink($target);
if (!$ok) {
    warez_fail(is_dir($target) ? 'Directory not empty or not writable' : 'Delete failed', 500);
}

warez_json(array('ok' => true));
