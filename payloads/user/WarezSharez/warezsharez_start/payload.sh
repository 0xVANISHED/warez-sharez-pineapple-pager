#!/bin/bash
# Title: WarezSharez - Start
# Description: (Re)starts the WarezSharez runtime - nginx, PHP-FPM, DNS hijack, and firewall redirects. Use after a reboot. Does not touch the AP.
# Author: 0xVANISHED
# Version: 2.0
# Category: Wireless

PORTAL_IP="172.16.52.1"
BRIDGE="br-lan"
WEB_ROOT="/www/warezsharez"
DNS_PORT="1053"

if [ ! -d "$WEB_ROOT" ] || [ ! -f /etc/nginx/nginx.conf.warezsharez.bak ]; then
    ERROR_DIALOG "WarezSharez is not installed. Run 'WarezSharez - Install' first."
    exit 1
fi

LOG "Starting WarezSharez runtime..."

# Services - free :80 from uhttpd so nginx can bind it (restored by Stop/Uninstall)
/etc/init.d/php8-fpm restart 2>/dev/null || true
/etc/init.d/umdns restart 2>/dev/null || /etc/init.d/umdns start 2>/dev/null || true   # re-advertise <hostname>.local (picks up a changed hostname)
/etc/init.d/uhttpd stop 2>/dev/null || true; killall uhttpd 2>/dev/null || true
/etc/init.d/nginx stop 2>/dev/null || true; killall nginx 2>/dev/null || true; sleep 1
/etc/init.d/nginx start; sleep 1

# Firewall redirects (idempotent re-add)
add_redirect() { # name proto dport destport [src_dip]
    uci show firewall | grep -q "name='$1'" && return
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
}
add_redirect "WarezSharez HTTP lan"    tcp 80  80          "!$PORTAL_IP"
add_redirect "WarezSharez HTTPS lan"   tcp 443 80          "!$PORTAL_IP"
add_redirect "WarezSharez DNS TCP lan" tcp 53  "$DNS_PORT"
add_redirect "WarezSharez DNS UDP lan" udp 53  "$DNS_PORT"
uci commit firewall
/etc/init.d/firewall restart

# DNS hijack
[ -f /tmp/warezsharez-dns.pid ] && kill "$(cat /tmp/warezsharez-dns.pid)" 2>/dev/null
kill $(netstat -plant 2>/dev/null | grep ":${DNS_PORT}" | awk '{print $NF}' | sed 's/\/dnsmasq//g') 2>/dev/null
dnsmasq --no-hosts --no-resolv --address=/#/${PORTAL_IP} --dns-forward-max=1 --cache-size=0 \
    -p ${DNS_PORT} --listen-address=0.0.0.0,::1 --bind-interfaces &
echo $! > /tmp/warezsharez-dns.pid
echo 1 > /proc/sys/net/ipv4/ip_forward
sysctl -w net.ipv6.conf.${BRIDGE}.disable_ipv6=1 2>/dev/null || true

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1/)
ALERT "WarezSharez started (portal HTTP ${HTTP_CODE}). Join '${SSID:-SHARE_UR_WAREZ}' - portal at http://${PORTAL_IP}/"
exit 0
