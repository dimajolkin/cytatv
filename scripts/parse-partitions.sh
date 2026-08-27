#!/usr/bin/env bash
# Извлечь blkdevparts / partition info из boot log
set -euo pipefail

LOG="${1:-$(cd "$(dirname "$0")/.." && pwd)/docs/boot-log.txt}"

if [[ ! -f "$LOG" ]]; then
  echo "Нет файла: $LOG"
  exit 1
fi

echo "=== Partition info from boot log ==="
grep -iE 'blkdevparts|Kernel command line|bootargs|mmcblk0:' "$LOG" || echo "(не найдено — нужен полный log с самого включения)"

echo ""
echo "=== Memory ==="
grep -iE 'Memory:|mem=|total memory|DDR' "$LOG" || echo "(не найдено)"

echo ""
echo "Сохраните blkdevparts для backup/flash через ADB (см. docs/linux-install.md)"
