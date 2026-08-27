#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/firmware/flash"
BASE_URL="https://leandro.azsat.org/2021-02-26"

mkdir -p "$DEST"

download() {
  local file="$1"
  local url="$BASE_URL/$file"
  if [[ -f "$DEST/$file" ]] && bzip2 -tv "$DEST/$file" &>/dev/null; then
    echo "OK (verified): $file"
    return 0
  fi
  [[ -f "$DEST/$file" ]] && rm -f "$DEST/$file"
  echo "Скачиваю: $file"
  curl -L --retry 3 --retry-delay 5 -o "$DEST/$file" "$url"
  if [[ "$file" == *.bz2 ]]; then
    bzip2 -tv "$DEST/$file" || { echo "CRC error in $file — удалите и скачайте снова"; exit 1; }
  fi
}

echo "=== e2d-hi3798cv200 firmware download ==="
echo "Папка: $DEST"
echo ""

download "ChangeLog.md"
download "e2d-armhf-pixel-20210226_K3.18.24.upk"
download "e2d-armhf-pixel-20210226_K4.4.35.upk"
download "e2d-armhf-pixel.img_20210226.tar.bz2"

echo ""
echo "Готово. Распаковка образа:"
echo "  cd $DEST && tar xjf e2d-armhf-pixel.img_20210226.tar.bz2"
echo ""
echo "Дальше: docs/linux-install.md"
