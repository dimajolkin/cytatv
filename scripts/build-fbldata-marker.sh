#!/usr/bin/env bash
# fbldata: маркер в bootargs env для проверки cold-boot cmdline.
# Ищем после boot: androidboot.fbldata=smoke1 в /proc/cmdline (UART или adb).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/firmware/cyta/extracted/partitions/fbldata.img"
OUT_DIR="$ROOT/firmware/e2d/boot-experiment"
OUT="$OUT_DIR/fbldata-cmdline-marker.img"
SMOKE="$OUT_DIR/fbldata-hybrid-smoke.img"

[[ -f "$SRC" ]] || { echo "нет $SRC"; exit 1; }
mkdir -p "$OUT_DIR"

python3 - "$SRC" "$OUT" "$SMOKE" <<'PY'
from pathlib import Path
import struct, sys, zlib

src, out_marker, out_smoke = map(Path, sys.argv[1:])
fb = bytearray(src.read_bytes())
ENV_OFF, ENV_SIZE = 0x600, 0x10000
assert ENV_OFF + ENV_SIZE <= len(fb)

def parse_env(buf):
    data = bytes(buf[ENV_OFF + 4 : ENV_OFF + ENV_SIZE])
    end = data.find(b"\x00\x00")
    if end < 0:
        end = len(data)
    vars, order = {}, []
    pos = 0
    while pos < end:
        z = data.find(b"\x00", pos)
        if z < 0:
            break
        s = data[pos:z]
        if b"=" in s:
            k, _, v = s.partition(b"=")
            vars[k] = v
            order.append(k)
        pos = z + 1
    return vars, order

def write_env(buf, vars, order):
    body = bytearray()
    for k in order:
        if k not in vars:
            continue
        body += k + b"=" + vars[k] + b"\x00"
    body += b"\x00"
    if len(body) + 4 > ENV_SIZE:
        raise SystemExit(f"env too big: {len(body)+4}")
    block = bytearray(ENV_SIZE)
    block[4 : 4 + len(body)] = body
    c = zlib.crc32(bytes(block[4:])) & 0xFFFFFFFF
    struct.pack_into("<I", block, 0, c)
    buf[ENV_OFF : ENV_OFF + ENV_SIZE] = block
    return c

# --- smoke: bootdelay only ---
smoke = bytearray(fb)
old, new = b"bootdelay=0", b"bootdelay=2"
i = smoke.find(old, ENV_OFF, ENV_OFF + ENV_SIZE)
if i < 0:
    raise SystemExit("bootdelay=0 not found")
smoke[i : i + len(old)] = new
c = zlib.crc32(bytes(smoke[ENV_OFF + 4 : ENV_OFF + ENV_SIZE])) & 0xFFFFFFFF
struct.pack_into("<I", smoke, ENV_OFF, c)
out_smoke.write_bytes(smoke)
print(f"wrote {out_smoke} CRC={c:08x} (bootdelay=2)")

# --- marker: append to bootargs ---
vars, order = parse_env(fb)
marker = b" androidboot.fbldata=smoke1"
if marker.strip() not in vars.get(b"bootargs", b""):
    vars[b"bootargs"] = vars[b"bootargs"] + marker
vars[b"bootdelay"] = b"2"
mark = bytearray(fb)
c2 = write_env(mark, vars, order)
# preserve header / tail
assert mark[:ENV_OFF] == fb[:ENV_OFF]
assert mark[ENV_OFF + ENV_SIZE :] == fb[ENV_OFF + ENV_SIZE :]
out_marker.write_bytes(mark)
print(f"wrote {out_marker} CRC={c2:08x}")
print("flash @ 1 MiB; check cmdline for androidboot.fbldata=smoke1")
print("rollback: firmware/cyta/extracted/partitions/fbldata.img")
PY
