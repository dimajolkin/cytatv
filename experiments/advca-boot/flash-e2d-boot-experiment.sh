#!/usr/bin/env bash
# ISP: эксперимент e2d multiboot (path B). Terminal.app + sudo.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BOOT="$ROOT/firmware/e2d/boot-experiment"
CYTA="$ROOT/firmware/cyta/extracted/partitions"
WRITER_DIR="${EMMC_WRITER_DIR:-$ROOT/../eMMC153-Writer}"
WORKER="${EMMC_WORKER:-$WRITER_DIR/eMMC153-Worker}"

DISK="${DISK:-}"
YES="${YES:-0}"
VERIFY="${VERIFY:-1}"
STAGE="${STAGE:-1}"
BOOTARGS="${BOOTARGS:-e2d-linux}"  # e2d | e2d-linux | cyta-hybrid | hybrid-smoke | hybrid-loglevel | cyta
WITH_SYSTEM="${WITH_SYSTEM:-0}"    # 1 = ещё system.img из firmware/custom

MiB=$((1024 * 1024))
OFF_FASTBOOT=$((34 * MiB))
OFF_BOOTARGS=$((38 * MiB))
OFF_BASEPARAM=$((73 * MiB))
OFF_KERNEL=$((141 * MiB))
OFF_SYSTEM=$((1886 * MiB))
LIM_KERNEL=$((15 * MiB))

die() { echo "ERROR: $*" >&2; exit 1; }

write_part() {
  local name="$1" img="$2" offset="$3"
  echo ""
  echo "=== $name @ $((offset / MiB)) MiB → $img ==="
  "$WORKER" write \
    --device "/dev/r$DISK" \
    --image "$img" \
    --offset "$offset" \
    $([[ "$VERIFY" == "1" ]] && echo --verify)
}

rollback() {
  need_cyta
  echo "=== ROLLBACK Cyta boot chain ==="
  write_part "fastboot" "$CYTA/fastboot.img" "$OFF_FASTBOOT"
  write_part "bootargs" "$CYTA/bootargs.img" "$OFF_BOOTARGS"
  write_part "baseparam" "$CYTA/baseparam.img" "$OFF_BASEPARAM"
  write_part "kernel" "$CYTA/kernel.img" "$OFF_KERNEL"
  echo ""
  echo "Rollback boot OK. system/logo — отдельно: q22e android-oem-hack flash"
}

need_cyta() {
  for f in fastboot.img bootargs.img baseparam.img kernel.img; do
    [[ -f "$CYTA/$f" ]] || die "нет $CYTA/$f"
  done
}

need_boot() {
  [[ -d "$BOOT" ]] || die "нет $BOOT — ./build-e2d-boot-experiment.sh"
  for f in fastboot.img baseparam.img kernel.img; do
    [[ -f "$BOOT/$f" ]] || die "нет $BOOT/$f"
  done
}

bootargs_file() {
  case "$BOOTARGS" in
    e2d) echo "$BOOT/bootargs-e2d.img" ;;
    e2d-linux) echo "$BOOT/bootargs-e2d-linux-default.img" ;;
    cyta-hybrid) echo "$BOOT/bootargs-cyta-hybrid.img" ;;
    hybrid-smoke) echo "$BOOT/bootargs-hybrid-smoke.img" ;;
    hybrid-loglevel) echo "$BOOT/bootargs-hybrid-loglevel.img" ;;
    cyta) echo "$CYTA/bootargs.img" ;;
    *) die "BOOTARGS=e2d|e2d-linux|cyta-hybrid|hybrid-smoke|hybrid-loglevel|cyta" ;;
  esac
}

if [[ "${1:-}" == "rollback" ]]; then
  [[ -n "$DISK" ]] || die "DISK=diskN"
  [[ "$(id -u)" -eq 0 ]] || die "sudo"
  if [[ ! -x "$WORKER" ]]; then
    (cd "$WRITER_DIR" && go build -o eMMC153-Worker ./cmd/worker)
  fi
  rollback
  exit 0
fi

need_boot
need_cyta

if [[ ! -x "$WORKER" ]]; then
  echo "=== build eMMC153-Worker ==="
  [[ -d "$WRITER_DIR" ]] || die "нет $WRITER_DIR"
  (cd "$WRITER_DIR" && go build -o eMMC153-Worker ./cmd/worker)
fi

echo "=== диски ==="
diskutil list | grep -E '^/dev/disk|external|#' || true

[[ -n "$DISK" ]] || die "DISK=diskN"
[[ "$DISK" =~ ^disk[0-9]+$ ]] || die "формат diskN"
[[ "$DISK" != "disk0" ]] || die "disk0 запрещён"
[[ "$(id -u)" -eq 0 ]] || die "sudo: YES=1 DISK=$DISK STAGE=$STAGE sudo -E $0"

BA="$(bootargs_file)"
[[ -f "$BA" ]] || die "нет $BA"

echo ""
echo "STAGE=$STAGE  BOOTARGS=$BOOTARGS  WITH_SYSTEM=$WITH_SYSTEM"
echo "Цель: /dev/r$DISK"
echo "Откат: YES=1 DISK=$DISK sudo -E $0 rollback"

case "$STAGE" in
  1)
    write_part "fastboot (e2d)" "$BOOT/fastboot.img" "$OFF_FASTBOOT"
    ;;
  2)
    write_part "fastboot (e2d)" "$BOOT/fastboot.img" "$OFF_FASTBOOT"
    write_part "bootargs ($BOOTARGS)" "$BA" "$OFF_BOOTARGS"
    write_part "baseparam (e2d)" "$BOOT/baseparam.img" "$OFF_BASEPARAM"
    ;;
  3|full)
    write_part "fastboot (e2d)" "$BOOT/fastboot.img" "$OFF_FASTBOOT"
    write_part "bootargs ($BOOTARGS)" "$BA" "$OFF_BOOTARGS"
    write_part "baseparam (e2d)" "$BOOT/baseparam.img" "$OFF_BASEPARAM"
    write_part "kernel (e2d boot.img)" "$BOOT/kernel.img" "$OFF_KERNEL"
    ;;
  bootargs-only)
    # только bootargs (hybrid smoke / cyta) — fastboot/baseparam не трогаем
    write_part "bootargs ($BOOTARGS)" "$BA" "$OFF_BOOTARGS"
    ;;
  *)
    die "STAGE=1|2|3|full|bootargs-only"
    ;;
esac

if [[ "$STAGE" == "full" || "$WITH_SYSTEM" == "1" ]]; then
  CUSTOM="$ROOT/firmware/custom"
  [[ -f "$CUSTOM/system.img" ]] || die "нет $CUSTOM/system.img"
  write_part "system (custom)" "$CUSTOM/system.img" "$OFF_SYSTEM"
fi

echo ""
echo "=== stage $STAGE OK ==="
echo "Чип → плата → UART: ./scripts/uart-capture.sh"
echo ""
echo "Ожидание:"
echo "  STAGE=1: bootmenu или отказ trustedcore/ADVCA"
echo "  STAGE=2: MENU на TV (bootdelay=2), разметка e2d — system Cyta может не совпасть"
echo "  STAGE=3: + e2d kernel; Linux: SD e2d + selectboot=0; Android: красная / selectboot=1"
echo ""
echo "Откат: YES=1 DISK=$DISK sudo -E $0 rollback"
