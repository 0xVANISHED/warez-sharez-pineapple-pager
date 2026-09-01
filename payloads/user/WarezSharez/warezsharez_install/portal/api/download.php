<?php
// GET download.php?path=<relative file>          -> serve INLINE (browser renders images/PDF/etc.)
// GET download.php?path=<relative file>&dl=1     -> force DOWNLOAD (attachment).
require_once __DIR__ . '/_lib.php';

$rel = isset($_GET['path']) ? $_GET['path'] : '';
$file = warez_resolve($rel, true, 'read'); // downloads may roam the whole read tree
if ($file === false || !is_file($file)) {
    warez_fail('File not found', 404);
}
if (!is_readable($file)) {
    warez_fail('File not readable', 403);
}

$name = basename($file);
$size = @filesize($file);
$dl   = isset($_GET['dl']) && $_GET['dl'] !== '0';
$ext  = strtolower(pathinfo($name, PATHINFO_EXTENSION));

// Extension -> MIME for inline rendering; anything unmapped downloads (octet-stream).
$mimes = array(
    'jpg'=>'image/jpeg','jpeg'=>'image/jpeg','png'=>'image/png','gif'=>'image/gif',
    'webp'=>'image/webp','bmp'=>'image/bmp','ico'=>'image/x-icon','heic'=>'image/heic',
    'avif'=>'image/avif','tif'=>'image/tiff','tiff'=>'image/tiff',
    'pdf'=>'application/pdf',
    'txt'=>'text/plain','log'=>'text/plain','md'=>'text/plain','csv'=>'text/plain',
    'json'=>'text/plain','ini'=>'text/plain','conf'=>'text/plain',
    'mp4'=>'video/mp4','webm'=>'video/webm','ogv'=>'video/ogg','mov'=>'video/quicktime',
    'mp3'=>'audio/mpeg','wav'=>'audio/wav','ogg'=>'audio/ogg','m4a'=>'audio/mp4','flac'=>'audio/flac',
);
$type = isset($mimes[$ext]) ? $mimes[$ext] : 'application/octet-stream';

// Never render user-uploaded active content inline (stored-XSS on an open share):
// html/svg/xml/js etc. are downloaded, not executed in the portal origin.
$active = array('html','htm','xhtml','shtml','svg','xml','js','mjs','mhtml','php','phtml');
$forceDownload = $dl || in_array($ext, $active, true) || $type === 'application/octet-stream';

// Clear any buffering so large files stream instead of buffering into RAM.
while (ob_get_level() > 0) { ob_end_clean(); }

$fn = str_replace('"', '', $name);
if ($forceDownload) {
    header('Content-Type: application/octet-stream');
    header('Content-Disposition: attachment; filename="' . $fn . '"');
} else {
    header('Content-Type: ' . $type);
    header('Content-Disposition: inline; filename="' . $fn . '"');
}
header('X-Content-Type-Options: nosniff');
if ($size !== false) { header('Content-Length: ' . $size); }
header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');
header('Pragma: no-cache');

$fp = fopen($file, 'rb');
if ($fp === false) { warez_fail('Cannot open file', 500); }
while (!feof($fp)) {
    echo fread($fp, 262144); // 256 KB chunks
    flush();
}
fclose($fp);
exit;
