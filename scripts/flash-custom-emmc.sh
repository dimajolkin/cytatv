#!/usr/bin/env bash
# Обёртка: custom Android → eMMC Socket через eMMC153-Worker batch.
# Запускать из Terminal.app: YES=1 DISK=diskN sudo -E ./scripts/flash-custom-emmc.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CUSTOM="${ANDROID_DIR:-$ROOT/firmware/custom}"
WRITER_DIR="${EMMC_WRITER_DIR:-$ROOT/../eMMC153-Writer}"
WORKER="${EMMC_WORKER:-$WRITER_DIR/eMMC153-Worker}"

DISK="${DISK:-}"
YES="${YES:-0}"
VERIFY="${VERIFY:-1}"

die() { echo "ERROR: $*" >&2; exit 1; }

[[ -f "$CUSTOM/logo.img" && -f "$CUSTOM/kernel.img" && -f "$CUSTOM/system.img" ]] \
  || die "нет logo/kernel/system в $CUSTOM — ./scripts/build-custom-android.sh"

if [[ ! -x "$WORKER" ]]; then
  echo "=== build eMMC153-Worker ==="
  [[ -d "$WRITER_DIR" ]] || die "нет $WRITER_DIR"
  (cd "$WRITER_DIR" && go build -o eMMC153-Worker ./cmd/worker)
  WORKER="$WRITER_DIR/eMMC153-Worker"
fi

echo "=== диски (Socket ~7.8G) ==="
diskutil list | grep -E '^/dev/disk|external|#' || true
echo ""

if [[ -z "$DISK" ]]; then
  for d in $(diskutil list | awk '/^\// && /external/{gsub(/\/dev\//,"",$1); print $1}'); do
    name="$(diskutil info "/dev/$d" 2>/dev/null | awk -F': *' '/Device \/ Media Name/{print $2}')"
    [[ "$name" == "Socket" ]] && DISK="$d" && break
  done
fi

[[ -n "$DISK" ]] || die "укажи DISK=diskN (Socket eMMC)"
[[ "$DISK" =~ ^disk[0-9]+$ ]] || die "формат diskN"
[[ "$DISK" != "disk0" ]] || die "disk0 запрещён"

MEDIA="$(diskutil info "/dev/$DISK" | awk -F': *' '/Device \/ Media Name/{print $2}')"
echo "Цель: /dev/r$DISK  media='$MEDIA'"
echo "Android: $CUSTOM"
[[ "$MEDIA" == "Socket" || "$YES" == "1" ]] || die "не Socket — YES=1 чтобы продолжить"

if [[ "$(id -u)" -ne 0 ]]; then
  die "нужен root: YES=1 DISK=$DISK sudo -E $0
(из Terminal.app с Full Disk Access; из Cursor osascript /dev/rdisk часто blocked)"
fi

VFLAG=()
[[ "$VERIFY" == "1" ]] && VFLAG=(--verify)

echo ""
echo "=== eMMC153-Worker batch --android ==="
"$WORKER" batch \
  --device "/dev/r$DISK" \
  --android "$CUSTOM" \
  "${VFLAG[@]+"${VFLAG[@]}"}"

echo ""
echo "Готово. Чип → плата → питание. UART: ./scripts/uart-capture.sh"
