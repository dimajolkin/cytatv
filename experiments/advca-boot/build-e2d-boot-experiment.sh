#!/usr/bin/env bash
# Эксперимент B: e2d multiboot (fastboot/bootargs/baseparam/kernel) для ISP.
# .upk переписывает boot-цепочку — на Cyta ADVCA может не загрузиться. Бэкап: firmware/cyta/.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FLASH="$ROOT/firmware/flash"
OUT="$ROOT/firmware/e2d/boot-experiment"
UPK="${UPK:-$FLASH/e2d-armhf-pixel-20210226_K3.18.24.upk}"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

MiB=$((1024 * 1024))
CYTA_BOOTARGS="$ROOT/firmware/cyta/extracted/partitions/bootargs.img"
KERNEL_SLOT=$((15 * MiB))

need() { [[ -f "$1" ]] || { echo "нет $1"; exit 1; }; }

need "$UPK"
need "$CYTA_BOOTARGS"

echo "=== extract $UPK ==="
unzip -q -o "$UPK" -d "$WORKDIR"

for f in fastboot.img bootargs.img baseparam.img boot.img; do
  need "$WORKDIR/$f"
done

mkdir -p "$OUT"

cp -f "$WORKDIR/fastboot.img" "$OUT/fastboot.img"
cp -f "$WORKDIR/baseparam.img" "$OUT/baseparam.img"

# boot.img на диске ~28M, полезная часть ~9M — укладываем в слот kernel 15M
python3 - "$WORKDIR/boot.img" "$OUT/kernel.img" "$KERNEL_SLOT" <<'PY'
import struct, sys, math

src, dst, slot = sys.argv[1], sys.argv[2], int(sys.argv[3])
data = open(src, "rb").read()
if data[:8] != b"ANDROID!":
    sys.exit("boot.img: нет ANDROID! magic")
ks = struct.unpack_from("<I", data, 8)[0]
rs = struct.unpack_from("<I", data, 16)[0]
ss = struct.unpack_from("<I", data, 24)[0]
ps = struct.unpack_from("<I", data, 36)[0]
need = (1 + math.ceil(ks / ps) + math.ceil(rs / ps) + math.ceil(ss / ps)) * ps
if need > slot:
    sys.exit(f"boot.img logic {need} B > kernel slot {slot} B")
open(dst, "wb").write(data[:need])
print(f"kernel.img: {need}/{slot} B ({need/1024/1024:.2f} MiB)")
PY

cp -f "$WORKDIR/bootargs.img" "$OUT/bootargs-e2d.img"

# default Android (selectboot=1) → Linux (0) для автозапуска e2d
python3 - "$WORKDIR/bootargs.img" "$OUT/bootargs-e2d-linux-default.img" <<'PY'
import sys
src, dst = sys.argv[1], sys.argv[2]
data = open(src, "rb").read()
if b"selectboot=1" in data:
    data = data.replace(b"selectboot=1", b"selectboot=0", 1)
elif b"selectboot=0" not in data:
    sys.exit("selectboot= не найден в bootargs")
open(dst, "wb").write(data)
print("bootargs: selectboot=0 (Linux default)")
PY

# Cyta blkdevparts + e2d bootmenu (env без ADVCA-обёртки — только для эксперимента)
python3 - "$WORKDIR/bootargs.img" "$CYTA_BOOTARGS" "$OUT/bootargs-cyta-hybrid.img" <<'PY'
import sys, re

e2d = open(sys.argv[1], "rb").read()
cyta = open(sys.argv[2], "rb").read()
idx = cyta.find(b"bootdelay=")
if idx < 0:
    sys.exit("Cyta bootargs: env не найден")
cyta_parts = re.search(rb"blkdevparts=[^\x00]+", cyta)
if not cyta_parts:
    sys.exit("Cyta bootargs: blkdevparts не найден")
parts = cyta_parts.group(0).decode("ascii", errors="replace")

# e2d env — текст между CRC и нулями; грубо: декодируем null-separated
text = e2d.decode("latin1", errors="replace")
vars = {}
for chunk in text.split("\x00"):
    if "=" in chunk and not chunk.startswith("\x00"):
        k, _, v = chunk.partition("=")
        if k.isprintable() and len(k) < 64:
            vars[k] = v

vars["bootargs"] = (
    "androidboot.selinux=disabled console=ttyAMA0,115200 "
    + parts
    + " hbcomp=/dev/block/mmcblk0p14"
)
vars["bootargsandroid"] = (
    "setenv bootargs 'androidboot.selinux=disabled console=ttyAMA0,115200 "
    + parts
    + " hbcomp=/dev/block/mmcblk0p14'"
)
vars["bootargslinux"] = (
    "setenv bootargs 'console=ttyAMA0,115200 root=/dev/mmcblk1p1 rw "
    + parts
    + " hbcomp=/dev/block/mmcblk0p14'"
)
# Cyta kernel @ 141 MiB → sector 0x46800 (512 B)
vars["android"] = "mmc read 0 0x1FFBFC0 0x46800 0xC800; run bootargsandroid; saveenv; bootm 0x1FFBFC0"
vars["linux"] = "mmc read 0 0x1FFBFC0 0x46800 0xC800; run bootargslinux; saveenv; bootm 0x1FFBFC0"
vars["selectboot"] = "0"
vars["bootdelay"] = "2"
vars["preboot"] = "bootmenu"

# U-Boot env: CRC32 + key=value\0... — упрощённо копируем e2d и патчим строки in-place
out = bytearray(e2d)
replacements = [
    (rb"selectboot=1", rb"selectboot=0"),
    (rb"selectboot=2", rb"selectboot=0"),
]
for old, new in replacements:
    if old in out:
        out.replace(old, new)

def set_var(blob: bytearray, key: str, value: str) -> None:
    old = f"{key}=".encode()
    start = blob.find(old)
    if start < 0:
        return
    end = blob.find(b"\x00", start)
    if end < 0:
        return
    new = f"{key}={value}".encode()
    segment = blob[start:end]
    if len(new) > len(segment):
        print(f"WARN: {key} не влезает in-place, пропуск")
        return
    blob[start:end] = new + b"\x00" * (len(segment) - len(new))

set_var(out, "bootargs", vars["bootargs"])
set_var(out, "bootargsandroid", vars["bootargsandroid"])
set_var(out, "bootargslinux", vars["bootargslinux"])
set_var(out, "android", vars["android"])
set_var(out, "linux", vars["linux"])
set_var(out, "selectboot", "0")

open(sys.argv[3], "wb").write(out)
print("bootargs-cyta-hybrid: e2d menu + Cyta blkdevparts + kernel@0x46800")
print("WARN: CRC env может быть битый — stage2 лучше с bootargs-e2d.img")
PY

cat > "$OUT/README.txt" <<EOF
e2d boot experiment (path B) — $(date -u +%Y-%m-%dT%H:%M:%SZ)

Файлы:
  fastboot.img                 — e2d bootmenu loader
  bootargs-e2d.img             — e2d env, default Android
  bootargs-e2d-linux-default.img — e2d env, default Linux (selectboot=0)
  bootargs-cyta-hybrid.img     — e2d menu + Cyta partition table (CRC может быть невалиден)
  baseparam.img
  kernel.img                   — e2d boot.img (Android boot image), <=15 MiB

ISP offsets (Q22E):
  fastboot   @ 34 MiB
  bootargs   @ 38 MiB
  baseparam  @ 73 MiB
  kernel     @ 141 MiB

Откат: ./flash-e2d-boot-experiment.sh rollback

Прошивка: STAGE=1|2|3|full YES=1 DISK=diskN sudo -E ./flash-e2d-boot-experiment.sh
EOF

echo ""
echo "Done: $OUT"
ls -lh "$OUT"
cat "$OUT/README.txt"
