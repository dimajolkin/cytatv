#!/usr/bin/env bash
# Build cytasu-daemon + su client → firmware/custom/assets/magisk-arm/
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/firmware/custom/assets/magisk-arm"
NDK=$(ls -d "$HOME/Library/Android/sdk/ndk"/*/ 2>/dev/null | sort -V | tail -1)
[[ -n "$NDK" ]] || { echo "нет NDK"; exit 1; }
API=21
TC="$NDK/toolchains/llvm/prebuilt/darwin-x86_64"
CC="$TC/bin/armv7a-linux-androideabi${API}-clang"
STRIP="$TC/bin/llvm-strip"
mkdir -p "$OUT"
"$CC" -O2 -static -o "$OUT/cytasu-daemon" "$(dirname "$0")/daemon.c"
"$CC" -O2 -static -o "$OUT/su" "$(dirname "$0")/su.c"
"$STRIP" "$OUT/cytasu-daemon" "$OUT/su"
ls -la "$OUT/cytasu-daemon" "$OUT/su"
