<?php
// OS captive-portal probe handler.
//   - Unauthorized client  -> 302 to the welcome page (so the sign-in popup shows our portal).
//   - Authorized client     -> return the success each OS expects, so the popup marks the
//                              network "connected" and closes on its own.
// A client becomes authorized when it taps "I'm in" on the welcome page (api/authorize.php).
$WL = '/tmp/warez_captive_ok';
$ip = isset($_SERVER['REMOTE_ADDR']) ? $_SERVER['REMOTE_ADDR'] : '';
$ok = ($ip !== '' && is_file($WL) && strpos("\n" . @file_get_contents($WL) . "\n", "\n{$ip}\n") !== false);

header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');

if (!$ok) {
    $host = (isset($_SERVER['HTTP_HOST']) && $_SERVER['HTTP_HOST'] !== '') ? $_SERVER['HTTP_HOST'] : '172.16.52.1';
    header('Location: http://' . $host . '/welcome.php', true, 302);
    exit;
}

$uri = strtolower(isset($_SERVER['REQUEST_URI']) ? $_SERVER['REQUEST_URI'] : '');
if (strpos($uri, '204') !== false) {                 // Android generate_204 / gen_204
    http_response_code(204);
    exit;
}
if (strpos($uri, 'ncsi') !== false) {                // Windows NCSI
    header('Content-Type: text/plain'); echo 'Microsoft NCSI'; exit;
}
if (strpos($uri, 'connecttest') !== false) {         // Windows connecttest
    header('Content-Type: text/plain'); echo 'Microsoft Connect Test'; exit;
}
// Apple (hotspot-detect / canonical / library-test) and default
header('Content-Type: text/html');
echo "<HTML><HEAD><TITLE>Success</TITLE></HEAD><BODY>Success</BODY></HTML>\n";
