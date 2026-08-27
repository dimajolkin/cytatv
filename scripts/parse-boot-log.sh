#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOG="${1:-$ROOT/docs/boot-log.txt}"
OUT="${2:-$ROOT/docs/inventory.md}"

if [[ ! -f "$LOG" ]]; then
  echo "Файл не найден: $LOG"
  exit 1
fi

extract() {
  local pattern="$1"
  grep -iE "$pattern" "$LOG" | head -5 || true
}

RAM=$(grep -iE 'Memory:|meminfo|total memory|[0-9]+[KMG]B.*RAM|DDR.*size' "$LOG" | head -3 || true)
FLASH=$(grep -iE 'MMC|eMMC|NAND|flash|mmcblk|partition|GPT' "$LOG" | head -10 || true)
KERNEL=$(grep -iE 'Linux version|Uncompressing Linux|booting the kernel' "$LOG" | head -3 || true)
BOOTARGS=$(grep -iE 'bootargs|console=tty' "$LOG" | head -3 || true)
CPU=$(grep -iE 'cpu|Cortex|processor|Hi3798' "$LOG" | head -5 || true)
ANDROID=$(grep -iE 'Android|init:|Starting kernel' "$LOG" | head -5 || true)
SECURITY=$(grep -iE '高安|secure|TEE|trustzone|verify' "$LOG" | head -3 || true)

{
  echo "# Inventory — Cyta STB Q22E"
  echo ""
  echo "Источник: \`$LOG\`"
  echo "Сгенерировано: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo ""
  echo "## Подтверждено из boot log"
  echo ""
  echo "| Параметр | Значение |"
  echo "|----------|----------|"
  echo "| Bootloader | HiSilicon compressed-boot v1.0.0 |"
  echo "| Kernel | Linux (сжатый образ, загружается) |"
  echo "| UART baud | 115200 (рабочий) |"
  echo ""
  echo "## CPU"
  echo ""
  if [[ -n "$CPU" ]]; then
    echo '```'
    echo "$CPU"
    echo '```'
  else
    echo "Не найдено в log. Ожидается: **Hi3798CV200**, 4× Cortex-A53 @ ~1.5 GHz."
  fi
  echo ""
  echo "## RAM"
  echo ""
  if [[ -n "$RAM" ]]; then
    echo '```'
    echo "$RAM"
    echo '```'
  else
    echo "Не найдено в log. Ожидается для Q22 CV200: **2 GB**."
    echo ""
    echo "> Перезагрузите с полным захватом с самого начала — строки \`Memory:\` идут раньше kernel."
  fi
  echo ""
  echo "## Flash / partitions"
  echo ""
  if [[ -n "$FLASH" ]]; then
    echo '```'
    echo "$FLASH"
    echo '```'
  else
    echo "Не найдено в log. Ожидается: **eMMC 4–8 GB**."
  fi
  echo ""
  echo "## Kernel / boot"
  echo ""
  if [[ -n "$KERNEL" ]]; then
    echo '```'
    echo "$KERNEL"
    echo '```'
  fi
  if [[ -n "$BOOTARGS" ]]; then
    echo ""
    echo "### bootargs"
    echo '```'
    echo "$BOOTARGS"
    echo '```'
  fi
  echo ""
  echo "## Android"
  echo ""
  if [[ -n "$ANDROID" ]]; then
    echo '```'
    echo "$ANDROID"
    echo '```'
  else
    echo "Строки Android init не попали в захват — нужен более длинный log после kernel boot."
  fi
  echo ""
  echo "## Security"
  echo ""
  if [[ -n "$SECURITY" ]]; then
    echo '```'
    echo "$SECURITY"
    echo '```'
  else
    echo "Признаков high-security (高安) в текущем log нет."
  fi
  echo ""
  echo "## Shell-команды (если получится доступ)"
  echo ""
  echo '```bash'
  echo "cat /proc/cpuinfo"
  echo "cat /proc/meminfo"
  echo "cat /proc/partitions"
  echo "ls -la /dev/block/platform/soc/by-name/"
  echo "df -h"
  echo "uname -a"
  echo '```'
} > "$OUT"

echo "Inventory записан: $OUT"
