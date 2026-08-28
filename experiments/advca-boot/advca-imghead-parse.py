#!/usr/bin/env python3
"""Парсер Hisilicon ADVCA ImgHead v2 + U-Boot env в bootargs."""
from __future__ import annotations

import argparse
import struct
import sys
import zlib
from pathlib import Path

MAGIC = b"Hisilicon_ADVCA_ImgHead_MagicNum"


def parse(path: Path) -> int:
    data = path.read_bytes()
    print(f"file: {path} ({len(data)} B)")
    if not data.startswith(MAGIC):
        print("NO ADVCA magic")
        print("first32:", data[:32].hex())
        return 1

    ver = data[32:40]
    total_end, data_off, payload_len, sig_off, hdr_sz = struct.unpack_from("<5I", data, 40)
    print(f"version:     {ver!r}")
    print(f"TotalEnd:    {total_end:#x}")
    print(f"DataOffset:  {data_off:#x}")
    print(f"PayloadLen:  {payload_len:#x}")
    print(f"SigOffset:   {sig_off:#x}")
    print(f"HeaderSize:  {hdr_sz:#x}")
    print(f"checks: TotalEnd==Sig+0x100 → {total_end == sig_off + 0x100}")
    print(f"        PayloadLen==Sig-Data → {payload_len == sig_off - data_off}")

    if data_off >= 0x100 and sig_off + 0x100 <= len(data):
        pre = data[data_off - 0x100 : data_off]
        post = data[sig_off - 0x100 : sig_off] if sig_off >= data_off + 0x100 else b""
        print(f"meta pre-payload == meta pre-sig: {pre == post} ({len(pre)} B)")
        print(f"RSA sig: {data[sig_off:total_end].hex()[:64]}...")

    if data_off + 4 < len(data) and data[data_off + 4 : data_off + 14] == b"bootdelay=":
        env = data[data_off : data_off + 0x10000]
        if len(env) == 0x10000:
            stored = struct.unpack_from("<I", env, 0)[0]
            calc = zlib.crc32(env[4:]) & 0xFFFFFFFF
            print(f"env CRC: stored={stored:08x} calc={calc:08x} match={stored == calc}")
            pos = 4
            print("env vars:")
            while pos < len(env) - 1:
                if env[pos] == 0 and env[pos + 1] == 0:
                    break
                z = env.find(b"\x00", pos)
                print(f"  {bytes(env[pos:z]).decode('latin1', errors='replace')}")
                pos = z + 1
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("image", type=Path)
    return parse(ap.parse_args().image)


if __name__ == "__main__":
    sys.exit(main())
