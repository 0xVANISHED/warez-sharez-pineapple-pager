<?php
// Router for `php -S` local development. Points the portal APIs at dummy
// files under dev/data/ and treats usb/* folders as placeholder drives.
$devRoot = __DIR__;
$data    = $devRoot . '/data';

if (!getenv('WAREZ_ROOT'))      { putenv('WAREZ_ROOT=' . $data . '/warezsharez'); }
if (!getenv('WAREZ_READ_ROOT')) { putenv('WAREZ_READ_ROOT=' . $data); }
if (!getenv('WAREZ_DEV'))       { putenv('WAREZ_DEV=1'); }

$portal = realpath($devRoot . '/../payloads/user/WarezSharez/warezsharez_install/portal');
if ($portal === false) {
    http_response_code(500);
    header('Content-Type: text/plain');
    echo "WarezSharez portal not found\n";
    return true;
}

$uri = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);
if ($uri === false || $uri === '' || $uri === '/') {
    require $portal . '/index.php';
    return true;
}

$file = $portal . $uri;
if (is_file($file)) {
    if (substr($file, -4) === '.php') {
        require $file;
        return true;
    }
    return false; // static assets (css/js)
}

http_response_code(404);
header('Content-Type: text/plain');
echo "Not found\n";
return true;
