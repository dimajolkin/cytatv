#!/usr/bin/env bash
# Скопировать firmware/e2d/usb → корень FAT32 USB (MENU + опционально img).
set -euo pipefail

DEST="${1:-}"
MODE="${2:-all}" # all | menu | img

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/firmware/e2d/usb"

if [[ -z "$DEST" || ! -d "$DEST" ]]; then
  echo "Usage: $0 /Volumes/USB_NAME [all|menu|img]"
  echo ""
  echo "Сначала: ./scripts/build-e2d.sh"
  echo "Тома:"
  ls /Volumes/ 2>/dev/null || true
  exit 1
fi

[[ -d "$SRC" ]] || { echo "нет $SRC — ./scripts/build-e2d.sh"; exit 1; }

echo "=== e2d → USB $DEST (mode=$MODE) ==="

copy_one() {
  local f="$1"
  [[ -e "$SRC/$f" ]] || { echo "нет $SRC/$f"; exit 1; }
  echo "→ $f"
  # clone если возможно
  rm -f "$DEST/$f"
  if cp -c "$SRC/$f" "$DEST/$f" 2>/dev/null; then
    :
  else
    cp -f "$SRC/$f" "$DEST/$f"
  fi
}

case "$MODE" in
  menu)
    copy_one "e2d-armhf-pixel-20210226_K3.18.24.upk"
    cp -f "$SRC/README.txt" "$DEST/e2d-README.txt" 2>/dev/null || true
    ;;
  img)
    copy_one "e2d-armhf-pixel.img"
    ;;
  all)
    copy_one "e2d-armhf-pixel-20210226_K3.18.24.upk"
    copy_one "e2d-armhf-pixel-20210226_K4.4.35.upk"
    echo "Копирую e2d-armhf-pixel.img (~3.7G)…"
    copy_one "e2d-armhf-pixel.img"
    cp -f "$SRC/README.txt" "$DEST/e2d-README.txt" 2>/dev/null || true
    ;;
  *)
    echo "mode: all|menu|img"
    exit 1
    ;;
esac

sync
echo "Готово. Вставь USB в ehci-порт STB."
echo "  MENU: поставь .upk из Android (не Cyta recovery OTA)"
echo "  Linux: MENU → синяя (нужна SD) или зелёная UPDT с img"
ls -lh "$DEST"/e2d-armhf-pixel* 2>/dev/null || ls -lh "$DEST" | head
