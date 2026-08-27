#!/usr/bin/env bash
set -euo pipefail

BAUD="${BAUD:-115200}"
LOG_DIR="$(cd "$(dirname "$0")/.." && pwd)/docs"
LOG_FILE="${LOG_DIR}/boot-log-$(date +%Y%m%d-%H%M%S).txt"
DEFAULT_LOG="${LOG_DIR}/boot-log.txt"

mkdir -p "$LOG_DIR"

find_port() {
  ls /dev/cu.* 2>/dev/null | grep -iE 'usb|serial|SLAB|wch|ch34|cp21|ftdi' | head -1
}

PORT="${1:-$(find_port)}"

if [[ -z "$PORT" ]]; then
  echo "USB-UART не найден. Доступные порты:"
  ls /dev/cu.* 2>/dev/null || true
  exit 1
fi

echo "Порт: $BAUD @ $PORT"
echo "Лог:  $LOG_FILE (+ symlink $DEFAULT_LOG)"
echo ""
echo "Подключение: adapter RX→board TX, adapter TX→board RX, GND→GND"
echo "Включите или перезагрузите приставку."
echo ""

if command -v picocom &>/dev/null; then
  picocom -b "$BAUD" --imap lfcrlf "$PORT" 2>&1 | tee "$LOG_FILE"
elif command -v screen &>/dev/null; then
  script -q "$LOG_FILE" screen "$PORT" "$BAUD"
else
  echo "Установите picocom: brew install picocom"
  exit 1
fi

ln -sf "$(basename "$LOG_FILE")" "$DEFAULT_LOG" 2>/dev/null || cp "$LOG_FILE" "$DEFAULT_LOG"
echo "Сохранено: $LOG_FILE"
