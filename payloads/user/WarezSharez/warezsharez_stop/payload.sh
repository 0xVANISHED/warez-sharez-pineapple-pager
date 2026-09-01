#!/bin/bash
# Title: WarezSharez - Stop
# Description: Stops the WarezSharez runtime (nginx/PHP/DNS hijack) and removes the firewall redirects. Files and the share stay installed. Re-enables IPv6 on the LAN.
# Author: 0xVANISHED
# Version: 2.0
# Category: Wireless

BRIDGE="br-lan"
DNS_PORT="1053"

LOG "Stopping WarezSharez runtime..."

# DNS hijack - kill by pidfile, by name, and by whatever holds :DNS_PORT
[ -f /tmp/warezsharez-dns.pid ] && kill -9 "$(cat /tmp/warezsharez-dns.pid)" 2>/dev/null
rm -f /tmp/warezsharez-dns.pid
pkill -9 -f "dnsmasq.*${DNS_PORT}" 2>/dev/null
for pid in $(netstat -plant 2>/dev/null | grep ":${DNS_PORT} " | awk '{print $NF}' | sed 's#/.*##' | grep -E '^[0-9]+$'); do kill -9 "$pid" 2>/dev/null; done

# Services - stop nginx, restore uhttpd on :80
/etc/init.d/nginx stop 2>/dev/null || true; killall nginx 2>/dev/null || true
/etc/init.d/php8-fpm stop 2>/dev/null || true
/etc/init.d/uhttpd start 2>/dev/null || true

# Remove our firewall redirects (highest index first)
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
/etc/init.d/firewall restart

# Re-enable IPv6 on the LAN
sysctl -w net.ipv6.conf.${BRIDGE}.disable_ipv6=0 2>/dev/null || true

ALERT "WarezSharez stopped. Files remain in /mmc/root/warezsharez. Run 'WarezSharez - Start' to bring it back."
exit 0
