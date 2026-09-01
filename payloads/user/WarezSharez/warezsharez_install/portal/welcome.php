<?php
// WarezSharez captive-portal splash / welcome page (served at "/").
// Its whole job: greet the user, show the bookmarkable address so they can get
// back after the captive popup closes, and hand them into the file browser.
header("Cache-Control: no-store, no-cache, must-revalidate, max-age=0");
header("Pragma: no-cache");

// Prefer the friendly mDNS name (e.g. pager.local) with the IP as a fallback. The
// Pager runs umdns advertising its hostname on br-lan, so <hostname>.local resolves
// to the portal IP on Apple/Windows; the IP always works (incl. Android).
$mdns    = strtolower(trim(php_uname('n')));
$mdnsUrl = $mdns !== '' ? 'http://' . $mdns . '.local/' : '';
$ip      = isset($_SERVER['SERVER_ADDR']) && $_SERVER['SERVER_ADDR'] !== '' ? $_SERVER['SERVER_ADDR'] : '172.16.52.1';
$ipUrl   = 'http://' . $ip . '/';
$appUrl  = $mdnsUrl !== '' ? $mdnsUrl : $ipUrl;
$appHost = $mdns !== '' ? $mdns . '.local' : $ip;
?><!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
  <meta http-equiv="Cache-Control" content="no-cache, no-store, must-revalidate">
  <title>Welcome :: WarezSharez</title>
  <link rel="stylesheet" href="assets/app.css">
</head>
<body class="min-h-screen" style="touch-action:manipulation">
  <div class="mx-auto max-w-md p-3 sm:p-4">

    <!-- Title bar -->
    <div class="warez-bevel bg-warez-panel">
      <div class="bg-warez-bar text-white px-3 py-1 flex items-center justify-between">
        <span class="font-bold tracking-wide">&#128190; WarezSharez</span>
        <span class="text-xs">SHARE_UR_WAREZ</span>
      </div>
      <div class="px-3 py-3 text-sm text-center">
        <div class="text-warez-accent font-bold mb-1">*** Welcome to the SHARE_UR_WAREZ drop zone ***</div>
        <div class="text-xs text-warez-line">Share files with everyone on this network &mdash; upload and download from the Pager and any plugged-in USB drive.</div>
      </div>
    </div>

    <!-- The address to open in a real browser after this popup closes. Copy it now. -->
    <div class="warez-bevel bg-warez-panel mt-2 p-3 text-center">
      <div class="text-xs text-warez-line mb-1">&#128278; Copy this address, then open it in your browser after this window closes:</div>
      <div id="warez-url" class="warez-bevel-in bg-white px-3 py-2 text-lg font-bold text-warez-ink break-all"><?= htmlspecialchars($appUrl) ?></div>
      <div class="mt-2">
        <button id="warez-copy" type="button" class="warez-bevel bg-warez-bg px-4 py-1 text-sm font-bold">&#128203; Copy address</button>
      </div>
<?php if ($mdnsUrl !== ''): ?>
      <div class="text-xs text-warez-line mt-2">or <?= htmlspecialchars($ipUrl) ?></div>
<?php endif; ?>
    </div>

    <!-- Enter: authorize this client so the OS dismisses the sign-in popup. -->
    <div class="text-center mt-3">
      <button id="warez-accept" type="button"
              class="inline-block warez-bevel bg-warez-bg px-6 py-3 text-base font-bold text-warez-ink">Enter, I copied the URL above</button>
    </div>

    <script>
    (function () {
      // Copy the address to the clipboard. navigator.clipboard needs HTTPS, and we're
      // plain HTTP, so fall back to the old execCommand path.
      function legacyCopy(text, cb) {
        try {
          var t = document.createElement('textarea');
          t.value = text; t.setAttribute('readonly', '');
          t.style.position = 'fixed'; t.style.top = '0'; t.style.opacity = '0';
          document.body.appendChild(t); t.focus(); t.select();
          try { t.setSelectionRange(0, text.length); } catch (e) {}
          document.execCommand('copy'); document.body.removeChild(t); cb();
        } catch (e) { /* leave the address on screen for manual copy */ }
      }
      var cp = document.getElementById('warez-copy');
      var urlEl = document.getElementById('warez-url');
      if (cp && urlEl) {
        cp.addEventListener('click', function () {
          var url = urlEl.textContent.trim();
          var done = function () { cp.textContent = '✓ Copied'; setTimeout(function () { cp.innerHTML = '&#128203; Copy address'; }, 1500); };
          if (navigator.clipboard && navigator.clipboard.writeText) {
            navigator.clipboard.writeText(url).then(done, function () { legacyCopy(url, done); });
          } else { legacyCopy(url, done); }
        });
      }

      var b = document.getElementById('warez-accept');
      if (!b) { return; }
      b.addEventListener('click', function () {
        b.disabled = true; b.textContent = 'Connecting...';
        // Whitelist this client, then hit a captive-check URL so the OS re-probes,
        // sees success, and closes the popup.
        var go = function () { window.location = '/hotspot-detect.html'; };
        try {
          var x = new XMLHttpRequest();
          x.open('POST', 'api/authorize.php', true);
          x.timeout = 4000;
          x.onreadystatechange = function () { if (x.readyState === 4) { go(); } };
          x.ontimeout = go; x.onerror = go;
          x.send();
        } catch (e) { go(); }
      });
    })();
    </script>

    <!-- Footer -->
    <div class="text-center text-xs text-warez-line mt-4 inline-flex items-center justify-center gap-1 w-full">
      <img src="assets/heart.svg" alt="" class="warez-icon" draggable="false" width="16" height="16">
      made by <a href="https://0xvanished.com/" class="text-warez-ink underline font-bold">0xVANISHED</a>
    </div>

  </div>
</body>
</html>
