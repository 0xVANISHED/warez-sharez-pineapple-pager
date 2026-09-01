<?php
// Shared helpers for the WarezSharez file API.
//
// Two boundaries, enforced by realpath containment:
//   READ  root: /mmc/root         - listing + downloads may roam this whole tree
//   WRITE root: /mmc/root/warezsharez - uploads + deletes are confined here only
// UI paths are always relative to the READ root.

// Read a config value from the process env (php-fpm `env[...]`) or the request
// env (nginx `fastcgi_param NAME "...";`, which lands in $_SERVER).
function warez_env($name) {
    $v = getenv($name);
    if (($v === false || $v === '') && isset($_SERVER[$name])) { $v = $_SERVER[$name]; }
    return ($v === false || $v === '') ? null : $v;
}

function warez_write_root() {
    $r = warez_env('WAREZ_ROOT');
    if (!$r) { $r = '/mmc/root/warezsharez'; }
    $rp = realpath($r);
    return $rp !== false ? $rp : rtrim($r, '/');
}

function warez_read_root() {
    $r = warez_env('WAREZ_READ_ROOT');
    if (!$r) { $r = dirname(warez_write_root()); } // parent of the share, e.g. /mmc/root
    $rp = realpath($r);
    return $rp !== false ? $rp : rtrim($r, '/');
}

function warez_allow_delete() {
    // Default: deletes ON. Turn off with WAREZ_ALLOW_DELETE=0 (env or fastcgi_param).
    $v = warez_env('WAREZ_ALLOW_DELETE');
    if ($v === null) { return true; }
    return !in_array(strtolower((string)$v), array('0', 'false', 'no', 'off'), true);
}

// True if absolute path $abs is $limit or lives underneath it.
function warez_within($abs, $limit) {
    $limit = rtrim($limit, '/');
    if ($abs === $limit) { return true; }
    return strncmp($abs, $limit . '/', strlen($limit) + 1) === 0;
}

// Resolve a client path (relative to the READ root) to an absolute path, confined
// to $boundary ('read' = whole readable tree, 'write' = the share only).
// $mustExist=false resolves the parent (for a not-yet-created upload target).
// Returns the absolute path, or false if it escapes the boundary / is invalid.
function warez_resolve($rel, $mustExist = true, $boundary = 'read') {
    $base = warez_read_root();
    $rel = str_replace('\\', '/', (string)$rel);
    $rel = ltrim($rel, '/');
    $full = $base . '/' . $rel;

    if ($mustExist) {
        $rp = realpath($full);
        if ($rp === false) { return false; }
    } else {
        $parent = realpath(dirname($full));
        if ($parent === false) { return false; }
        $rp = $parent . '/' . basename($full);
    }

    $limit = ($boundary === 'write') ? warez_write_root() : warez_read_root();
    if (!warez_within($rp, $limit)) { return false; }
    return $rp;
}

// True if $path sits on a different filesystem than its parent (i.e. a mountpoint,
// such as an auto-mounted USB drive under the share's usb/ folder).
function warez_is_mount($path) {
    // Local-dev placeholder drives: directories directly under write_root/usb are
    // treated as mounts even when they share the host filesystem (no real USB).
    $dev = warez_env('WAREZ_DEV');
    if ($dev && !in_array(strtolower((string)$dev), array('0', 'false', 'no', 'off'), true)) {
        $usb = realpath(warez_write_root() . '/usb');
        $rp  = realpath($path);
        if ($usb && $rp && is_dir($rp) && dirname($rp) === $usb) { return true; }
    }
    $a = @stat($path);
    $b = @stat(dirname($path));
    if (!$a || !$b) { return false; }
    return $a['dev'] !== $b['dev'];
}

// OS/filesystem junk that shouldn't clutter the listing (macOS/Windows/Linux metadata).
function warez_is_junk($name) {
    $lc = strtolower($name);
    static $exact = array(
        // macOS
        '.ds_store', '.localized', '.apdisk', '.volumeicon.icns', '.spotlight-v100',
        '.fseventsd', '.trashes', '.temporaryitems', '.documentrevisions-v100',
        '.pkinstallsandboxmanager', '.com.apple.timemachine.donotpresent',
        '.com.apple.timemachine.supported', '.appledouble', '.appledb', '.appledesktop',
        'network trash folder', 'temporary items',
        // Windows
        'system volume information', '$recycle.bin', 'recycler', 'recycled',
        'thumbs.db', 'ehthumbs.db', 'ehthumbs_vista.db', 'desktop.ini', 'autorun.inf',
        // Linux / other
        'lost+found', '.metadata_never_index',
    );
    if (in_array($lc, $exact, true)) { return true; }
    if (strncmp($lc, '._', 2) === 0) { return true; }               // macOS AppleDouble sidecars (._foo)
    if (strncmp($lc, '~$', 2) === 0) { return true; }               // MS Office lock/temp files (~$doc)
    if (preg_match('/^\.trash-[0-9]+$/', $lc)) { return true; }     // Linux per-user trash (.Trash-1000)
    if (preg_match('/^found\.[0-9]{3}$/', $lc)) { return true; }    // chkdsk recovered clusters (FOUND.000)
    return false;
}

function warez_json($data, $status = 200) {
    http_response_code($status);
    header('Content-Type: application/json');
    header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');
    echo json_encode($data);
    exit;
}

function warez_fail($msg, $status = 400) {
    warez_json(array('ok' => false, 'error' => $msg), $status);
}

// Keep an uploaded filename to a safe basename.
function warez_safe_name($name) {
    $name = basename(str_replace('\\', '/', (string)$name));
    $name = preg_replace('/[\x00-\x1f\x7f]/', '', $name);   // strip control chars
    $name = ltrim($name, '.');                               // no leading dots
    if ($name === '' ) { $name = 'upload_' . time(); }
    return $name;
}
