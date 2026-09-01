#!/bin/bash
# Title: WarezSharez - Status
# Description: Shows WarezSharez runtime state (nginx/PHP/DNS/firewall), the Open AP SSID, share usage, and mounted USB drives.
# Author: 0xVANISHED
# Version: 2.0
# Category: Wireless

PORTAL_IP="172.16.52.1"
WEB_ROOT="/www/warezsharez"
WAREZ_DATA="/mmc/root/warezsharez"
DNS_PORT="1053"

pgrep nginx >/dev/null 2>&1 && NGINX="running" || NGINX="stopped"
( pgrep -f php-fpm >/dev/null 2>&1 || pgrep -f php8-fpm >/dev/null 2>&1 ) && PHP="running" || PHP="stopped"
netstat -plant 2>/dev/null | grep -q ":${DNS_PORT}" && DNS="active" || DNS="off"
RULES=$(uci show firewall 2>/dev/null | grep -c "WarezSharez.*lan")
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1/ 2>/dev/null)

# Open AP SSID (we don't manage it - just report what PineAP's Open AP is set to)
SSID="$(uci get wireless.wlan0open.ssid 2>/dev/null)"
OPEN_DIS="$(uci get wireless.wlan0open.disabled 2>/dev/null)"
if [ -z "$SSID" ]; then AP="(open AP not found)"
elif [ "$OPEN_DIS" = "1" ]; then AP="'${SSID}' (DISABLED - enable it in PineAP)"
else AP="'${SSID}' (on)"; fi

USAGE="$(du -sh "$WAREZ_DATA" 2>/dev/null | awk '{print $1}')"; [ -z "$USAGE" ] && USAGE="0"

USB=""
if [ -d "${WAREZ_DATA}/usb" ]; then
    for d in "${WAREZ_DATA}/usb"/*; do
        [ -d "$d" ] || continue
        mountpoint -q "$d" 2>/dev/null && USB="${USB}\n  - $(basename "$d") ($(df -h "$d" 2>/dev/null | awk 'NR==2{print $3"/"$2}'))"
    done
fi
[ -z "$USB" ] && USB="\n  (none)"

INSTALLED="yes"; [ -d "$WEB_ROOT" ] || INSTALLED="NO (run Install)"

WARN=""
if [ "$SSID" != "SHARE_UR_WAREZ" ]; then
    WARN="\n\n!! Open AP SSID is ${AP}. For WarezSharez, enable an Open AP named SHARE_UR_WAREZ in PineAP (open, no filters)."
elif [ "$OPEN_DIS" = "1" ]; then
    WARN="\n\n!! The Open AP is disabled - enable it in PineAP so clients can join."
fi

LOG "WarezSharez status:"
LOG "  Installed : ${INSTALLED}"
LOG "  nginx     : ${NGINX} (HTTP ${HTTP_CODE})"
LOG "  php-fpm   : ${PHP}"
LOG "  DNS hijack: ${DNS} (:${DNS_PORT})"
LOG "  Firewall  : ${RULES}/4 redirect rules"
LOG "  Open AP   : ${AP}"
LOG "  Share     : ${WAREZ_DATA} (${USAGE} used)"
LOG "  USB       :${USB}"

PROMPT "WarezSharez\nInstalled: ${INSTALLED}\nnginx: ${NGINX} (HTTP ${HTTP_CODE})  php: ${PHP}\nDNS hijack: ${DNS}  firewall: ${RULES}/4\nOpen AP: ${AP}\nURL: http://${PORTAL_IP}/\nShare: ${USAGE} used\nUSB:${USB}${WARN}"
exit 0
