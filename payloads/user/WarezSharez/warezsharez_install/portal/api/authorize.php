<?php
// Whitelist the calling client so OS captive probes start returning "success",
// which lets the captive sign-in popup mark the network connected and close.
header('Content-Type: application/json');
header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');
$WL = '/tmp/warez_captive_ok';
$ip = isset($_SERVER['REMOTE_ADDR']) ? $_SERVER['REMOTE_ADDR'] : '';
if ($ip !== '' && preg_match('/^[0-9a-fA-F:.]{3,45}$/', $ip)) {   // IPv4/IPv6 chars only
    $have = is_file($WL) ? "\n" . @file_get_contents($WL) . "\n" : "\n";
    if (strpos($have, "\n{$ip}\n") === false) {
        @file_put_contents($WL, $ip . "\n", FILE_APPEND | LOCK_EX);
    }
}
echo json_encode(array('ok' => true));
