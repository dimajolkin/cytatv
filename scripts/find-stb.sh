#!/usr/bin/env bash
# Поиск Cyta STB на прямом Ethernet-подключении к Mac (USB-LAN en9)
set -euo pipefail

IFACE="${1:-en9}"
STB_MAC_PREFIX="c4:b8:b4"  # Huawei Q22E label

echo "=== Поиск STB на $IFACE ==="
ifconfig "$IFACE" 2>/dev/null | grep -E 'inet |status|media' || { echo "Интерфейс $IFACE не найден"; exit 1; }
echo ""

CURRENT_IP=$(ifconfig "$IFACE" | awk '/inet / && !/inet6/ {print $2; exit}')
if [[ "$CURRENT_IP" == 169.254.* ]]; then
  echo "Link-local ($CURRENT_IP) — DHCP нет, нужен статический IP."
  echo ""
  echo "  sudo ifconfig $IFACE inet 192.168.100.1 netmask 255.255.255.0 up"
  echo "  ./scripts/find-stb.sh $IFACE"
  echo ""
fi

if [[ "$CURRENT_IP" == 192.168.100.* ]]; then
  echo "Сканирую 192.168.100.0/24..."
  nmap -sn -e "$IFACE" 192.168.100.0/24 2>/dev/null | grep -E 'Nmap scan report|Host is up|MAC Address' || echo "  (хостов не найдено)"
fi

echo ""
echo "=== ARP ==="
arp -an | grep -i "$IFACE" | grep -v incomplete || echo "  (пусто)"
arp -an | grep -i "$STB_MAC_PREFIX" || echo "  MAC приставки ($STB_MAC_PREFIX) не найден"

echo ""
echo "=== ADB probe ==="
FOUND=0
while read -r ip; do
  [[ -z "$ip" || "$ip" == *255 ]] && continue
  [[ "$ip" == "$CURRENT_IP" ]] && continue
  if nc -z -w 1 -G 1 "$ip" 5555 2>/dev/null; then
    echo "ADB OPEN: $ip:5555"
    adb connect "$ip:5555" 2>/dev/null || true
    adb -s "$ip:5555" shell getprop ro.product.model 2>/dev/null || true
    FOUND=1
  fi
done < <(arp -an | grep "$IFACE" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | sort -u)

[[ "$FOUND" -eq 0 ]] && echo "  ADB не найден"

echo ""
echo "STB MAC (наклейка): C4:B8:B4:8F:00:FC"
echo "Mac IP на $IFACE: ${CURRENT_IP:-нет}"
