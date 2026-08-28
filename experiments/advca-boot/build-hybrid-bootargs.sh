#!/usr/bin/env bash
# Hybrid bootargs: Cyta ADVCA header + правка U-Boot env + пересчёт CRC.
# RSA/meta не трогаем — smoke проверяет, покрывает ли подпись env.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SRC="$ROOT/firmware/cyta/extracted/partitions/bootargs.img"
OUT_DIR="$ROOT/firmware/e2d/boot-experiment"
mkdir -p "$OUT_DIR"

[[ -f "$SRC" ]] || { echo "нет $SRC"; exit 1; }

python3 - "$SRC" "$OUT_DIR" <<'PY'
from pathlib import Path
import struct, zlib, sys

src, out_dir = Path(sys.argv[1]), Path(sys.argv[2])
raw = bytearray(src.read_bytes())

MAGIC = b"Hisilicon_ADVCA_ImgHead_MagicNum"
assert raw.startswith(MAGIC), "не ADVCA bootargs"
total_end, data_off, payload_len, sig_off, hdr_sz = struct.unpack_from("<5I", raw, 40)
assert data_off == 0x2000 and total_end == 0x12200

ENV_OFF, ENV_SIZE = 0x2000, 0x10000

def env_crc(buf: bytearray) -> None:
    c = zlib.crc32(buf[ENV_OFF + 4 : ENV_OFF + ENV_SIZE]) & 0xFFFFFFFF
    struct.pack_into("<I", buf, ENV_OFF, c)

def patch_same_len(buf: bytearray, old: bytes, new: bytes, label: str) -> None:
    if len(old) != len(new):
        raise SystemExit(f"{label}: длины должны совпадать {len(old)}!={len(new)}")
    i = buf.find(old, ENV_OFF, ENV_OFF + ENV_SIZE)
    if i < 0:
        raise SystemExit(f"{label}: не найдено {old!r}")
    buf[i : i + len(old)] = new
    print(f"patch {label}: {old!r} → {new!r} @ {i:#x}")

# --- smoke: только bootdelay (same-length) ---
smoke = bytearray(raw)
patch_same_len(smoke, b"bootdelay=0", b"bootdelay=2", "smoke")
env_crc(smoke)
# meta/RSA must stay
assert smoke[0x1F00:0x2000] == raw[0x1F00:0x2000]
assert smoke[0x12000:0x12200] == raw[0x12000:0x12200]
p = out_dir / "bootargs-hybrid-smoke.img"
p.write_bytes(smoke)
print(f"wrote {p} ({len(smoke)} B)")

# --- extended: loader-loglevel + bootdelay (всё same-length) ---
ext = bytearray(raw)
patch_same_len(ext, b"bootdelay=0", b"bootdelay=2", "ext")
patch_same_len(ext, b"loader-loglevel=4", b"loader-loglevel=7", "ext")
env_crc(ext)
assert ext[0x12000:0x12200] == raw[0x12000:0x12200]
p2 = out_dir / "bootargs-hybrid-loglevel.img"
p2.write_bytes(ext)
print(f"wrote {p2}")

# verify CRCs
for path in (p, p2):
    d = path.read_bytes()
    st = struct.unpack_from("<I", d, ENV_OFF)[0]
    calc = zlib.crc32(d[ENV_OFF + 4 : ENV_OFF + ENV_SIZE]) & 0xFFFFFFFF
    print(f"CRC {path.name}: {st:08x} ok={st==calc}")

print(
    """
Гипотеза:
  Android после hybrid-smoke → env НЕ в RSA (можно расширять меню)
  Boot loop → env в RSA (нужен ключ OEM / другой путь)

Flash:
  YES=1 DISK=diskN BOOTARGS=hybrid-smoke STAGE=bootargs-only \\
    sudo -E ./flash-e2d-boot-experiment.sh
"""
)
PY
