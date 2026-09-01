<?php
// GET list.php?path=<relative dir>  ->  JSON directory listing under the share root.
require_once __DIR__ . '/_lib.php';

$rel = isset($_GET['path']) ? $_GET['path'] : '';
$dir = warez_resolve($rel, true, 'read');
if ($dir === false || !is_dir($dir)) {
    warez_fail('Directory not found', 404);
}

$entries = array();
$dh = @opendir($dir);
if ($dh === false) {
    warez_fail('Cannot read directory', 500);
}
$atShareRoot = ($dir === warez_write_root());
while (($name = readdir($dh)) !== false) {
    if ($name === '.' || $name === '..') { continue; }
    // Never show the 'usb' container itself - mounted drives are surfaced at the
    // top level below instead.
    if ($name === 'usb' && $atShareRoot) { continue; }
    // Hide OS/filesystem junk (.DS_Store, System Volume Information, $RECYCLE.BIN, ...).
    if (warez_is_junk($name)) { continue; }
    $full = $dir . '/' . $name;
    $isDir = is_dir($full);
    $entries[] = array(
        'name'  => $name,
        'type'  => $isDir ? 'dir' : 'file',
        'size'  => $isDir ? null : @filesize($full),
        'mtime' => @filemtime($full),
        'mount' => $isDir ? warez_is_mount($full) : false,
    );
}
closedir($dh);

// At the share root, surface each mounted USB drive as a top-level entry. 'nav' is the
// real sub-path (usb/<label>) so the UI navigates correctly without a visible usb folder.
if ($atShareRoot && is_dir($dir . '/usb')) {
    $uh = @opendir($dir . '/usb');
    if ($uh !== false) {
        while (($u = readdir($uh)) !== false) {
            if ($u === '.' || $u === '..') { continue; }
            $up = $dir . '/usb/' . $u;
            if (is_dir($up) && warez_is_mount($up)) {
                $entries[] = array(
                    'name'  => $u,
                    'type'  => 'dir',
                    'size'  => null,
                    'mtime' => @filemtime($up),
                    'mount' => true,
                    'nav'   => 'usb/' . $u,
                );
            }
        }
        closedir($uh);
    }
}

// Uploads and deletes are both confined to the share (write root) and need the dir
// writable on disk. Deletes additionally honor the WAREZ_ALLOW_DELETE toggle (default on).
$inShare = warez_within($dir, warez_write_root()) && is_writable($dir);
warez_json(array(
    'ok'        => true,
    'path'      => ltrim(str_replace('\\', '/', (string)$rel), '/'),
    'writable'  => $inShare,
    'deletable' => $inShare && warez_allow_delete(),
    'entries'   => $entries,
));
