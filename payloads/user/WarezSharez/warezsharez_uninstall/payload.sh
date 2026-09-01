#!/bin/bash
# Title: WarezSharez - Uninstall
# Description: Backs out all WarezSharez changes - DNS hijack, firewall redirects, nginx config, USB hook - and DELETES /mmc/root/warezsharez and its files. USB drives are unmounted first (their contents are NOT wiped). nginx/PHP packages are left installed.
# Author: 0xVANISHED
# Version: 2.0
# Category: Wireless

BRIDGE="br-lan"
DNS_PORT="1053"
SSID="SHARE_UR_WAREZ"
WEB_ROOT="/www/warezsharez"
WAREZ_DATA="/mmc/root/warezsharez"
NGINX_CONF="/etc/nginx/nginx.conf"
NGINX_BAK="/etc/nginx/nginx.conf.warezsharez.bak"
AP_BACKUP="/root/.warezsharez_ap.bak"

resp=$(CONFIRMATION_DIALOG "Uninstall WarezSharez? This DELETES ${WAREZ_DATA} and ALL local files in it. USB drives are unmounted first, so files ON the drives are NOT wiped.") || exit 1
if [ "$resp" != "$DUCKYSCRIPT_USER_CONFIRMED" ]; then
    PROMPT "Uninstall cancelled. Nothing changed."
    exit 0
fi

LOG "Uninstalling WarezSharez..."

# 1. Unmount USB drives under the share (protect their data first!)
if [ -d "${WAREZ_DATA}/usb" ]; then
    for d in "${WAREZ_DATA}/usb"/*; do
        [ -d "$d" ] || continue
        mountpoint -q "$d" 2>/dev/null && { umount "$d" 2>/dev/null || umount -l "$d" 2>/dev/null; LOG "  unmounted $d"; }
    done
fi

# 2. Stop DNS hijack - by pidfile, by name, and by whatever holds :DNS_PORT
[ -f /tmp/warezsharez-dns.pid ] && kill -9 "$(cat /tmp/warezsharez-dns.pid)" 2>/dev/null
rm -f /tmp/warezsharez-dns.pid /tmp/warez_captive_ok
pkill -9 -f "dnsmasq.*${DNS_PORT}" 2>/dev/null
for pid in $(netstat -plant 2>/dev/null | grep ":${DNS_PORT} " | awk '{print $NF}' | sed 's#/.*##' | grep -E '^[0-9]+$'); do kill -9 "$pid" 2>/dev/null; done

# 3. Stop services
/etc/init.d/nginx stop 2>/dev/null || true; killall nginx 2>/dev/null || true
/etc/init.d/php8-fpm stop 2>/dev/null || true

# 4. Remove our firewall redirects (highest index first)
while true; do
    LAST=""
    for s in $(uci show firewall | grep '@redirect\[' | cut -d. -f2 | cut -d= -f1 | sort -u); do
        nm=$(uci get firewall.$s.name 2>/dev/null)
        echo "$nm" | grep -qi "warezsharez" || continue
        idx=$(echo "$s" | sed 's/@redirect\[\([0-9]*\)\].*/\1/')
        { [ -z "$LAST" ] || [ "$idx" -gt "$LAST" ]; } && LAST="$idx"
    done
    [ -z "$LAST" ] && break
    uci delete firewall.@redirect[$LAST] 2>/dev/null
done
uci commit firewall

# 5. Restore nginx config + re-enable UCI nginx
if [ -f "$NGINX_BAK" ]; then
    mv "$NGINX_BAK" "$NGINX_CONF"
    LOG "  restored original nginx.conf"
fi
uci set nginx.global.uci_enable=true 2>/dev/null || true
uci commit nginx 2>/dev/null || true
rm -f /etc/php8/99-warezsharez.ini

# 6. Re-enable IPv6, restart firewall, return :80 to uhttpd (the pre-install default)
sysctl -w net.ipv6.conf.${BRIDGE}.disable_ipv6=0 2>/dev/null || true
/etc/init.d/firewall restart
/etc/init.d/nginx stop 2>/dev/null || true; killall nginx 2>/dev/null || true
/etc/init.d/uhttpd start 2>/dev/null || true
# Stop advertising the hostname (umdns) that we enabled (package stays installed)
/etc/init.d/umdns stop 2>/dev/null || true
/etc/init.d/umdns disable 2>/dev/null || true

# Restore the Open AP to its pre-install state (or disable it if no backup found)
if uci show wireless.wlan0open >/dev/null 2>&1; then
    if [ -f "$AP_BACKUP" ]; then
        . "$AP_BACKUP"   # OLD_SSID / OLD_ENC / OLD_DISABLED
        [ -n "$OLD_SSID" ]     && uci set wireless.wlan0open.ssid="$OLD_SSID"
        [ -n "$OLD_ENC" ]      && uci set wireless.wlan0open.encryption="$OLD_ENC"
        [ -n "$OLD_DISABLED" ] && uci set wireless.wlan0open.disabled="$OLD_DISABLED"
        uci commit wireless
        wifi reload 2>/dev/null || /sbin/wifi up 2>/dev/null
        LOG "  restored Open AP (ssid='${OLD_SSID}', disabled='${OLD_DISABLED}')"
        rm -f "$AP_BACKUP"
    elif [ "$(uci get wireless.wlan0open.ssid 2>/dev/null)" = "$SSID" ]; then
        uci set wireless.wlan0open.disabled='1'
        uci commit wireless
        wifi reload 2>/dev/null || /sbin/wifi up 2>/dev/null
        LOG "  no AP backup - disabled the Open AP (was broadcasting ${SSID})"
    fi
fi

# 7. Remove hook, portal code, and the share data
rm -f /etc/hotplug.d/block/30-warezsharez
rm -rf "$WEB_ROOT"
rm -rf "$WAREZ_DATA"

LOG "=================================================="
LOG "WarezSharez uninstalled. Open AP restored to its pre-install state."
LOG "  Left in place: nginx, php8/php8-fpm, umdns, USB/filesystem packages."
LOG "=================================================="
ALERT "WarezSharez removed. Share deleted; USB drives were unmounted (not wiped); Open AP restored."
exit 0
