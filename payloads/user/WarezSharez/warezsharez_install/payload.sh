#!/bin/bash
# Title: WarezSharez - Install and Run
# Description: Stands up the WarezSharez file-share captive portal on the LAN (nginx + PHP + DNS hijack), auto-mounts USB, and enables the Open AP 'SHARE_UR_WAREZ'. Leans on PineAP for the AP radio/DHCP - does not reconfigure bridges.
# Author: 0xVANISHED
# Version: 2.0
# Category: Wireless

# ====================================================================
# Model: layer a captive portal onto the LAN the Pineapple's Open AP
# already serves (br-lan / 172.16.52.1). We do NOT reconfigure wireless,
# bridges, or DHCP - PineAP owns those. This mirrors the GoodPortal approach
# and avoids the connectivity breakage of moving the AP onto a custom bridge.
# ====================================================================
PORTAL_IP="172.16.52.1"
BRIDGE="br-lan"
SSID="SHARE_UR_WAREZ"
WEB_ROOT="/www/warezsharez"          # nginx doc root: the portal CODE
WAREZ_DATA="/mmc/root/warezsharez"   # the file-share DATA the app reads/writes
DNS_PORT="1053"
NGINX_CONF="/etc/nginx/nginx.conf"
NGINX_BAK="/etc/nginx/nginx.conf.warezsharez.bak"
AP_BACKUP="/root/.warezsharez_ap.bak"   # pre-install Open AP config, for Uninstall to restore

# The Pager copies payload.sh into /tmp to run it, so $0's dir is not the payload
# folder. Find portal/ + hotplug/ next to the on-disk payload.sh.
find_src_dir() {
    local d self_dir
    self_dir="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
    for d in \
        "$self_dir" \
        /mmc/root/payloads/user/WarezSharez/warezsharez_install \
        /root/payloads/user/WarezSharez/warezsharez_install
    do
        [ -d "$d/portal" ] && [ -f "$d/hotplug/30-warezsharez" ] && { echo "$d"; return 0; }
    done
    for d in $(find /mmc/root/payloads /root/payloads -type d -name warezsharez_install 2>/dev/null); do
        [ -d "$d/portal" ] && [ -f "$d/hotplug/30-warezsharez" ] && { echo "$d"; return 0; }
    done
    return 1
}
SRC_DIR="$(find_src_dir)"
PORTAL_SRC="${SRC_DIR}/portal"
HOTPLUG_SRC="${SRC_DIR}/hotplug/30-warezsharez"

LOG "Installing WarezSharez (GoodPortal-style, no Evil Portal)..."
LOG "Source: ${SRC_DIR:-<not found>}"

if [ -z "$SRC_DIR" ] || [ ! -d "$PORTAL_SRC" ] || [ ! -f "$HOTPLUG_SRC" ]; then
    LOG "ERROR: portal/ or hotplug/ not found next to warezsharez_install/payload.sh."
    ERROR_DIALOG "WarezSharez files incomplete.\n\nCopy the whole warezsharez_install folder (payload.sh + portal/ + hotplug/) to the Pager payloads."
    exit 1
fi

# ====================================================================
# STEP 1: Packages (nginx + PHP + USB/filesystem support)
# ====================================================================
LOG "Step 1: Checking packages..."
NEED=""
for pkg in nginx php8 php8-fpm php8-cgi umdns block-mount kmod-usb-storage kmod-fs-vfat kmod-fs-exfat kmod-fs-ext4 kmod-fs-ntfs3 dosfstools; do
    opkg list-installed | grep -q "^${pkg} " || NEED="$NEED $pkg"
done
if [ -n "$NEED" ]; then
    if ! ping -c1 -W2 google.com &>/dev/null; then
        LOG "ERROR: No internet - cannot install:$NEED"
        ERROR_DIALOG "No internet. Enable WiFi Client Mode so packages ($NEED) can install, then re-run."
        exit 1
    fi
    LOG "Installing:$NEED"
    opkg update
    opkg install $NEED
    if ! command -v nginx >/dev/null 2>&1 || ! opkg list-installed | grep -q "^php8-fpm "; then
        LOG "ERROR: nginx/php8-fpm install failed."
        ERROR_DIALOG "nginx or php8-fpm failed to install. Check opkg (Pager 1.0.4 has a broken feed line in /etc/opkg/distfeeds.conf)."
        exit 1
    fi
else
    LOG "SUCCESS: all packages already installed"
fi

# Advertise <hostname>.local on the LAN (umdns) so clients can use e.g. pager.local
# instead of the IP. Default umdns config already targets the 'lan' network.
/etc/init.d/umdns enable 2>/dev/null || true
/etc/init.d/umdns restart 2>/dev/null || /etc/init.d/umdns start 2>/dev/null || true
LOG "  mDNS responder (umdns) enabled - $(cat /proc/sys/kernel/hostname 2>/dev/null).local"

# ====================================================================
# STEP 2: Share folder (the file-share data)
# ====================================================================
LOG "Step 2: Creating share folder ${WAREZ_DATA}..."
mkdir -p "${WAREZ_DATA}/usb"
chmod -R 777 "${WAREZ_DATA}"

# ====================================================================
# STEP 3: Install the portal code to the nginx doc root
# ====================================================================
LOG "Step 3: Installing portal to ${WEB_ROOT}..."
mkdir -p "$WEB_ROOT"
cp -r "${PORTAL_SRC}/." "${WEB_ROOT}/"
chmod 755 /www "$WEB_ROOT" 2>/dev/null || true
find "$WEB_ROOT" -type d -exec chmod 755 {} \; 2>/dev/null || true
find "$WEB_ROOT" -type f -exec chmod 644 {} \; 2>/dev/null || true
LOG "SUCCESS: portal installed"

# ====================================================================
# STEP 4: USB auto-mount hook + mount anything already plugged in
# ====================================================================
LOG "Step 4: Installing USB auto-mount hook..."
mkdir -p /etc/hotplug.d/block
cp "$HOTPLUG_SRC" /etc/hotplug.d/block/30-warezsharez
chmod +x /etc/hotplug.d/block/30-warezsharez
for dev in /dev/sd[a-z][0-9]*; do
    [ -b "$dev" ] || continue
    LOG "Mounting already-attached $dev..."
    ACTION=add DEVNAME="$(basename "$dev")" /etc/hotplug.d/block/30-warezsharez
done

# ====================================================================
# STEP 5: Configure PHP (fixes "No input file specified" on OpenWrt)
# ====================================================================
LOG "Step 5: Configuring PHP..."
[ -f /etc/php.ini ] && sed -i 's/^doc_root = "\/www"/doc_root =/' /etc/php.ini 2>/dev/null || true
mkdir -p /etc/php8
cat > /etc/php8/99-warezsharez.ini << 'PHPINI'
cgi.force_redirect = 0
cgi.fix_pathinfo = 1
upload_max_filesize = 2047M
post_max_size = 2047M
max_execution_time = 0
max_input_time = -1
PHPINI
# NOTE: 2047M (not higher) - this is 32-bit MIPS, so >2GB overflows the size setting.
# php-fpm stays as 'nobody' (it refuses to run a pool as root); the USB hotplug mounts
# drives world-writable so 'nobody' can write to them (the share itself is already 777).
/etc/init.d/php8-fpm restart 2>/dev/null || true
sleep 1

# Detect the PHP-FPM socket
if [ -S /var/run/php8-fpm.sock ]; then FPM_SOCK="/var/run/php8-fpm.sock"
elif [ -S /var/run/php-fpm.sock ]; then FPM_SOCK="/var/run/php-fpm.sock"
else FPM_SOCK="/var/run/php8-fpm.sock"; LOG "  WARNING: FPM socket not found, using $FPM_SOCK"; fi

# ====================================================================
# STEP 6: Write our nginx.conf (backup the original first)
# ====================================================================
LOG "Step 6: Configuring nginx..."
uci set nginx.global.uci_enable=false 2>/dev/null || true
uci commit nginx 2>/dev/null || true
[ -f "$NGINX_BAK" ] || cp "$NGINX_CONF" "$NGINX_BAK" 2>/dev/null || true

cat > "$NGINX_CONF" << 'NGINXEOF'
user root root;
worker_processes 1;
events { worker_connections 1024; }
http {
    include mime.types;
    default_type text/html;
    sendfile on;
    keepalive_timeout 65;
    client_max_body_size 0;

    server {
        listen 80 default_server;
        server_name _;
NGINXEOF
echo "        root ${WEB_ROOT};" >> "$NGINX_CONF"
cat >> "$NGINX_CONF" << 'NGINXEOF'
        index index.php index.html;

        # OS captive-portal probes -> captive.php: redirect to the welcome page until the
        # client taps "I'm in", then return each OS's success so the popup closes itself.
        location = /generate_204 { rewrite ^ /captive.php last; }
        location = /gen_204 { rewrite ^ /captive.php last; }
        location = /connecttest.txt { rewrite ^ /captive.php last; }
        location = /success.txt { rewrite ^ /captive.php last; }
        location = /ncsi.txt { rewrite ^ /captive.php last; }
        location = /hotspot-detect.html { rewrite ^ /captive.php last; }
        location = /canonical.html { rewrite ^ /captive.php last; }
        location = /library/test/success.html { rewrite ^ /captive.php last; }
NGINXEOF
cat >> "$NGINX_CONF" << NGINXEOF

        location ~ \.php\$ {
            fastcgi_pass unix:${FPM_SOCK};
            fastcgi_index index.php;
            include fastcgi_params;
            fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
            fastcgi_param WAREZ_ROOT "${WAREZ_DATA}";
            fastcgi_read_timeout 3600;
        }
NGINXEOF
cat >> "$NGINX_CONF" << 'NGINXEOF'

        location / { try_files $uri $uri/ =404; }

        error_page 404 = @fallback;
        location @fallback { rewrite ^ /index.php last; }
    }
}
NGINXEOF

LOG "Validating nginx config..."
if ! nginx -t 2>&1 | grep -q "successful"; then
    LOG "ERROR: nginx config invalid - restoring backup"
    nginx -t 2>&1 | while read l; do LOG "  $l"; done
    [ -f "$NGINX_BAK" ] && cp "$NGINX_BAK" "$NGINX_CONF"
    ERROR_DIALOG "nginx config invalid. Backup restored. Check logs."
    exit 1
fi
/etc/init.d/php8-fpm restart 2>/dev/null || true
# Free port 80: on the Pager, uhttpd owns :80 by default (it serves the bare /www
# directory listing you'd otherwise see). Stop it so nginx can bind :80.
# Stop/Uninstall bring uhttpd back.
/etc/init.d/uhttpd stop 2>/dev/null || true; killall uhttpd 2>/dev/null || true
/etc/init.d/nginx stop 2>/dev/null || true; killall nginx 2>/dev/null || true; sleep 1
/etc/init.d/nginx start
sleep 2
# Who owns :80 now? grep the whole matching netstat line (program column formatting varies).
L80="$(netstat -plant 2>/dev/null | awk '$4 ~ /:80$/')"
if echo "$L80" | grep -q uhttpd; then
    LOG "  ERROR: uhttpd still holds :80"
    ERROR_DIALOG "uhttpd still owns port 80 - nginx could not bind it. Try again, or manually run: /etc/init.d/uhttpd stop"
    exit 1
elif echo "$L80" | grep -q nginx; then
    LOG "  nginx is serving :80"
else
    LOG "  note: :80 owner unclear from netstat - verifying by content below"
fi

# ====================================================================
# STEP 7: Firewall redirects (HTTP/HTTPS -> portal, DNS -> rogue :1053)
# ====================================================================
LOG "Step 7: Configuring firewall redirects..."
add_redirect() { # name proto dport destport [src_dip]
    uci show firewall | grep -q "name='$1'" && { LOG "  rule '$1' exists"; return; }
    uci add firewall redirect >/dev/null
    uci set firewall.@redirect[-1].name="$1"
    uci set firewall.@redirect[-1].src='lan'
    [ -n "$5" ] && uci set firewall.@redirect[-1].src_dip="$5"
    uci set firewall.@redirect[-1].proto="$2"
    uci set firewall.@redirect[-1].src_dport="$3"
    uci set firewall.@redirect[-1].dest_ip="$PORTAL_IP"
    uci set firewall.@redirect[-1].dest_port="$4"
    uci set firewall.@redirect[-1].target='DNAT'
    uci set firewall.@redirect[-1].enabled='1'
    LOG "  added '$1'"
}
add_redirect "WarezSharez HTTP lan"    tcp 80  80          "!$PORTAL_IP"
add_redirect "WarezSharez HTTPS lan"   tcp 443 80          "!$PORTAL_IP"
add_redirect "WarezSharez DNS TCP lan" tcp 53  "$DNS_PORT"
add_redirect "WarezSharez DNS UDP lan" udp 53  "$DNS_PORT"
uci commit firewall
/etc/init.d/firewall restart

# ====================================================================
# STEP 8: DNS hijack (rogue dnsmasq) + forwarding, without touching system dnsmasq
# ====================================================================
LOG "Step 8: Starting DNS hijack on :${DNS_PORT}..."
[ -f /tmp/warezsharez-dns.pid ] && kill "$(cat /tmp/warezsharez-dns.pid)" 2>/dev/null
kill $(netstat -plant 2>/dev/null | grep ":${DNS_PORT}" | awk '{print $NF}' | sed 's/\/dnsmasq//g') 2>/dev/null
dnsmasq --no-hosts --no-resolv --address=/#/${PORTAL_IP} --dns-forward-max=1 --cache-size=0 \
    -p ${DNS_PORT} --listen-address=0.0.0.0,::1 --bind-interfaces &
echo $! > /tmp/warezsharez-dns.pid
echo 1 > /proc/sys/net/ipv4/ip_forward
sysctl -w net.ipv6.conf.${BRIDGE}.disable_ipv6=1 2>/dev/null || true

# ====================================================================
# STEP 9: Open AP - set SSID + enable (the same uci the PineAP UI writes)
# ====================================================================
LOG "Step 9: Configuring Open AP '${SSID}'..."
if uci show wireless.wlan0open >/dev/null 2>&1; then
    # Save the pre-install Open AP config once, so Uninstall can restore it.
    if [ ! -f "$AP_BACKUP" ]; then
        {
            echo "OLD_SSID='$(uci get wireless.wlan0open.ssid 2>/dev/null)'"
            echo "OLD_ENC='$(uci get wireless.wlan0open.encryption 2>/dev/null)'"
            echo "OLD_DISABLED='$(uci get wireless.wlan0open.disabled 2>/dev/null)'"
        } > "$AP_BACKUP"
    fi
    # Ensure the SSID/encryption/visibility are ours, and (separately) that it's ON.
    # Only reload wifi if something actually changed, to avoid a needless bounce.
    NEED_RELOAD=0
    if [ "$(uci get wireless.wlan0open.ssid 2>/dev/null)" != "$SSID" ]; then
        uci set wireless.wlan0open.ssid="$SSID"
        uci set wireless.wlan0open.encryption='none'
        uci set wireless.wlan0open.hidden='0'
        NEED_RELOAD=1
    fi
    # Turn the open AP ON (this is the key bit - it may be disabled from an edit/toggle)
    if [ "$(uci get wireless.wlan0open.disabled 2>/dev/null)" != "0" ]; then
        uci set wireless.wlan0open.disabled='0'
        NEED_RELOAD=1
    fi
    # Also make sure the radio hosting it isn't disabled
    RADIO="$(uci get wireless.wlan0open.device 2>/dev/null)"
    if [ -n "$RADIO" ] && [ "$(uci get wireless.${RADIO}.disabled 2>/dev/null)" = "1" ]; then
        uci set wireless.${RADIO}.disabled='0'
        NEED_RELOAD=1
    fi
    if [ "$NEED_RELOAD" = "1" ]; then
        uci commit wireless
        wifi reload 2>/dev/null || /sbin/wifi up 2>/dev/null
        LOG "  Open AP '${SSID}' set and ENABLED (wifi reloaded)"
    else
        LOG "  Open AP already '${SSID}' and enabled - no change"
    fi
else
    LOG "  WARNING: wlan0open not found"
    PROMPT "Could not find the Open AP interface (wlan0open). Set the Open AP SSID to '${SSID}' manually in PineAP."
fi

# ====================================================================
# STEP 10: Verify
# ====================================================================
LOG "Step 10: Verifying..."
BODY="$(curl -s http://127.0.0.1/)"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1/)
if echo "$BODY" | grep -qi "WarezSharez"; then
    LOG "  SUCCESS: our portal is being served (HTTP ${HTTP_CODE})"
elif echo "$BODY" | grep -qiE "Index of|<?php"; then
    LOG "  ERROR: :80 is serving a directory listing / raw PHP, not our portal"
    ERROR_DIALOG "Port 80 isn't serving the WarezSharez portal (looks like uhttpd's file listing, or PHP isn't executing). Check that nginx+php8-fpm are running."
else
    LOG "  WARNING: unexpected response on :80 (HTTP ${HTTP_CODE})"
fi
netstat -plant 2>/dev/null | grep -q ":${DNS_PORT}" && LOG "  DNS hijack active" || LOG "  WARNING: DNS hijack not listening"
RULES=$(uci show firewall | grep -c "WarezSharez.*lan")
LOG "  firewall rules: ${RULES}/4"

LOG "=================================================="
LOG "WarezSharez installed (GoodPortal-style)."
LOG "  Portal : http://${PORTAL_IP}/  (served from ${WEB_ROOT})"
LOG "  Data   : ${WAREZ_DATA}  (+ usb/<label>)"
LOG "=================================================="
ALERT "WarezSharez is up and the Open AP '${SSID}' is broadcasting. Join it - the portal pops up. Reversible with 'WarezSharez - Uninstall'."
exit 0
