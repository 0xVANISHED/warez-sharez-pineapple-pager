<?php
// POST upload.php?path=<relative dir>  with multipart field files[]  ->  saves into that dir.
require_once __DIR__ . '/_lib.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    warez_fail('POST required', 405);
}

$rel = isset($_GET['path']) ? $_GET['path'] : '';
$dir = warez_resolve($rel, true, 'read');
if ($dir === false || !is_dir($dir)) {
    warez_fail('Target directory not found', 404);
}
// Uploads are confined to the share (write root), even though reads roam wider.
if (!warez_within($dir, warez_write_root())) {
    warez_fail('Uploads are only allowed inside the WarezSharez folder', 403);
}
if (!is_writable($dir)) {
    warez_fail('Target directory is read-only', 403);
}
if (empty($_FILES['files'])) {
    // Detect the common "upload exceeded php limits" case (empty POST).
    if (empty($_POST) && (int)($_SERVER['CONTENT_LENGTH'] ?? 0) > 0) {
        warez_fail('Upload too large (exceeds server limit)', 413);
    }
    warez_fail('No files in request', 400);
}

$files = $_FILES['files'];
$count = 0;
$errors = array();
$written = array();

// Normalize single-vs-multiple into arrays.
$names = is_array($files['name']) ? $files['name'] : array($files['name']);
$tmps  = is_array($files['tmp_name']) ? $files['tmp_name'] : array($files['tmp_name']);
$errs  = is_array($files['error']) ? $files['error'] : array($files['error']);

for ($i = 0; $i < count($names); $i++) {
    if ($errs[$i] !== UPLOAD_ERR_OK) {
        $errors[] = $names[$i] . ' (error ' . $errs[$i] . ')';
        continue;
    }
    $safe = warez_safe_name($names[$i]);
    $dest = $dir . '/' . $safe;

    // Avoid clobbering: append -1, -2, ... if the name is taken.
    if (file_exists($dest)) {
        $dot = strrpos($safe, '.');
        $base = $dot === false ? $safe : substr($safe, 0, $dot);
        $ext  = $dot === false ? '' : substr($safe, $dot);
        $n = 1;
        do { $dest = $dir . '/' . $base . '-' . $n . $ext; $n++; } while (file_exists($dest));
    }

    if (move_uploaded_file($tmps[$i], $dest)) {
        @chmod($dest, 0644);
        $written[] = $dest;
        $count++;
    } else {
        $errors[] = $safe . ' (write failed)';
    }
}

if ($count === 0) {
    warez_fail('Upload failed: ' . implode('; ', $errors), 500);
}

// Flush to disk so pulling a USB drive right after upload doesn't lose the data.
// vfat buffers writes - the filename lands but the data blocks may not without a sync.
foreach ($written as $p) {
    $h = @fopen($p, 'r');
    if ($h) { if (function_exists('fsync')) { @fsync($h); } @fclose($h); }
}
if (function_exists('exec')) { @exec('sync'); }   // flush all filesystems (incl. USB)

warez_json(array('ok' => true, 'count' => $count, 'errors' => $errors));
