#!/usr/bin/env python3
"""Clear DT_FLAGS_1 in ELF32 LE binaries (old Android Bionic rejects DF_1_PIE|NOW)."""
from __future__ import annotations

import struct
import sys
from pathlib import Path

DT_FLAGS_1 = 0x6FFFFFFB


def clear_file(path: Path) -> int:
    data = bytearray(path.read_bytes())
    if data[:4] != b"\x7fELF" or data[4] != 1 or data[5] != 1:
        print(f"{path}: skip (need ELF32 LE)", file=sys.stderr)
        return 0
    e_phoff = struct.unpack_from("<I", data, 28)[0]
    e_phentsize, e_phnum = struct.unpack_from("<HH", data, 42)
    fixed = 0
    for i in range(e_phnum):
        off = e_phoff + i * e_phentsize
        p_type, p_offset, _, _, p_filesz, *_ = struct.unpack_from("<IIIIIIII", data, off)
        if p_type != 2:
            continue
        j = 0
        while j + 8 <= p_filesz:
            tag, val = struct.unpack_from("<iI", data, p_offset + j)
            if tag == 0:
                break
            if tag == DT_FLAGS_1 and val != 0:
                print(f"{path.name}: DT_FLAGS_1 {val:#x} -> 0")
                struct.pack_into("<iI", data, p_offset + j, DT_FLAGS_1, 0)
                fixed += 1
            j += 8
    if fixed:
        path.write_bytes(data)
    return fixed


def main() -> int:
    if len(sys.argv) < 2:
        print(f"usage: {sys.argv[0]} <elf>...", file=sys.stderr)
        return 2
    total = 0
    for arg in sys.argv[1:]:
        total += clear_file(Path(arg))
    print(f"cleared {total} DT_FLAGS_1 entr(y/ies)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
