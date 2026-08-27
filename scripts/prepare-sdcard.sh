#!/usr/bin/env bash
set -euo pipefail

IMG="${1:-}"

if [[ -z "$IMG" || ! -f "$IMG" ]]; then
  echo "Usage: $0 <path/to/e2d-armhf-pixel.img>"
  echo ""
  echo "Сначала: ./scripts/build-e2d.sh"
  echo "  образ: firmware/e2d/sd/e2d-armhf-pixel.img"
  echo ""
  echo "Неинтерактивно: YES=1 DISK=diskN $0 firmware/e2d/sd/e2d-armhf-pixel.img"
  exit 1
fi

echo "=== Запись e2d на microSD ==="
echo "Образ: $IMG ($(du -h "$IMG" | cut -f1))"
echo ""
echo "Доступные диски:"
diskutil list | grep -E '^/dev/disk|external|#:'
echo ""

if [[ -n "${DISK:-}" && "${YES:-}" == "1" ]]; then
  :
elif [[ -n "${DISK:-}" ]]; then
  read -r -p "Подтвердите запись на $DISK (yes): " CONFIRM
  [[ "$CONFIRM" == "yes" ]] || { echo "Отменено"; exit 1; }
else
  read -r -p "Введите diskN (например disk4, БЕЗ r): " DISK
fi

if [[ ! "$DISK" =~ ^disk[0-9]+$ ]]; then
  echo "Неверный формат: $DISK"
  exit 1
fi

# Защита: не писать во внутренний диск Mac
if [[ "$DISK" == "disk0" ]]; then
  echo "Отказ: disk0 — системный диск"
  exit 1
fi

INFO="$(diskutil info "/dev/$DISK" 2>/dev/null || true)"
MEDIA="$(echo "$INFO" | awk -F': *' '/Device \/ Media Name/ {print $2}')"
PROTO="$(echo "$INFO" | awk -F': *' '/Protocol:/ {print $2}')"
# disk0 / Apple SSD — нельзя. Built-in SDXC Reader (Internal + Secure Digital) — можно.
if [[ "$DISK" == "disk0" ]] || echo "$INFO" | grep -qi 'Protocol:.*Apple Fabric\|Media Name:.*APPLE SSD'; then
  echo "Отказ: системный диск Mac"
  exit 1
fi
if echo "$INFO" | grep -qi 'Device Location:.*Internal' \
  && ! echo "$PROTO $MEDIA" | grep -qiE 'Secure Digital|SDXC|SD Card|Card Reader'; then
  echo "Отказ: внутренний диск (не SD-ридер):"
  echo "$INFO" | grep -E 'Device Node|Media Name|Protocol|Location' || true
  exit 1
fi

echo "Цель: /dev/$DISK  media='$MEDIA' protocol='$PROTO'"
echo "Будет записано — все данные на этом диске уничтожены!"

if [[ "${YES:-}" != "1" ]]; then
  read -r -p "Подтвердите (yes): " CONFIRM
  [[ "$CONFIRM" == "yes" ]] || { echo "Отменено"; exit 1; }
fi

diskutil unmountDisk "/dev/$DISK" || true
if [[ "$(id -u)" -eq 0 ]]; then
  dd if="$IMG" of="/dev/r$DISK" bs=4m status=progress
else
  echo "Нужен sudo (Terminal.app)…"
  sudo dd if="$IMG" of="/dev/r$DISK" bs=4m status=progress
fi
sync
diskutil eject "/dev/$DISK" || true

echo "SD готова. Вставьте в STB → MENU → синяя кнопка (Linux)."
