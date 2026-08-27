#!/usr/bin/env bash
# Direct link: Mac USB-Ethernet (en9) ↔ Q22E
# Fixed: MAC c4:b8:b4:bf:ab:ab → 192.168.88.91
set -euo pipefail

IFACE="${IFACE:-en9}"
GW="192.168.88.1"
STB_IP="192.168.88.91"
STB_MAC="c4:b8:b4:bf:ab:ab"
CONF="/tmp/cytatv-en9-dnsmasq.conf"
PIDF="/tmp/cytatv-en9-dnsmasq.pid"
LEASE="/tmp/cytatv-en9-leases"
LOG="/tmp/cytatv-en9-dnsmasq.log"
DNSMASQ="${DNSMASQ:-/opt/homebrew/sbin/dnsmasq}"

cat >"$CONF" <<EOF
interface=$IFACE
bind-interfaces
except-interface=lo
dhcp-range=192.168.88.50,192.168.88.100,255.255.255.0,12h
dhcp-option=3,$GW
dhcp-option=6,8.8.8.8
dhcp-host=$STB_MAC,$STB_IP,q22e,infinite
log-dhcp
EOF

sudo ifconfig "$IFACE" inet "$GW" netmask 255.255.255.0
if [[ -f "$PIDF" ]]; then sudo kill "$(cat "$PIDF")" 2>/dev/null || true; fi
sudo pkill -f "dnsmasq.*cytatv-en9" 2>/dev/null || true
sleep 1
printf '0 %s %s q22e 01:%s\n' "$STB_MAC" "$STB_IP" "$STB_MAC" | sudo tee "$LEASE" >/dev/null
sudo "$DNSMASQ" \
  --conf-file="$CONF" \
  --pid-file="$PIDF" \
  --dhcp-leasefile="$LEASE" \
  --log-facility="$LOG" \
  --port=0

echo "Mac $GW ($IFACE) → STB $STB_IP ($STB_MAC)"
ping -c 1 -W 1000 "$STB_IP" || true
echo "adb connect $STB_IP:5555"
