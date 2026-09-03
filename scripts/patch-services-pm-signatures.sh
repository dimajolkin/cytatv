#!/usr/bin/env bash
# Мок проверки подписей в PackageManagerService.compareSignatures* → всегда MATCH (0).
# services.jar на стоке пустой (код в oat/arm/services.odex). Деодексим, патчим, кладём classes.dex в jar.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FW="${FW:-$ROOT/firmware/cyta/extracted/filesystems/system/framework}"
OUT="${OUT:-$ROOT/firmware/custom/assets/services.jar}"
WORKDIR="${WORKDIR:-$ROOT/firmware/patches/services-build}"
DOCKER_IMG="${DOCKER_IMG:-cytatv-android:dev}"

ODEX="$FW/oat/arm/services.odex"
BOOT="$FW/arm/boot.oat"
[[ -f "$ODEX" && -f "$BOOT" ]] || { echo "нет $ODEX или $BOOT"; exit 1; }

mkdir -p "$WORKDIR" "$(dirname "$OUT")"
SMALI="$WORKDIR/smali"
DEX="$WORKDIR/classes.dex"

echo "=== baksmali deodex services.odex ==="
rm -rf "$SMALI"
docker run --rm \
  -v "$FW:/fw:ro" \
  -v "$WORKDIR:/work" \
  "$DOCKER_IMG" \
  baksmali deodex -a 24 -b /fw/arm/boot.oat -o /work/smali /fw/oat/arm/services.odex

PMS="$SMALI/com/android/server/pm/PackageManagerService.smali"
[[ -f "$PMS" ]] || { echo "нет $PMS"; exit 1; }

python3 - "$PMS" <<'PY'
import re, sys
path = sys.argv[1]
text = open(path, encoding="utf-8", errors="replace").read()

replacements = [
    (
        r"\.method static compareSignatures\(\[Landroid/content/pm/Signature;\[Landroid/content/pm/Signature;\)I"
        r".*?\n\.end method",
        ".method static compareSignatures([Landroid/content/pm/Signature;[Landroid/content/pm/Signature;)I\n"
        "    .registers 16\n"
        "    const/4 v0, 0x0\n"
        "    return v0\n"
        ".end method",
    ),
    (
        r"\.method private compareSignaturesCompat\(Lcom/android/server/pm/PackageSignatures;Landroid/content/pm/PackageParser\$Package;\)I"
        r".*?\n\.end method",
        ".method private compareSignaturesCompat(Lcom/android/server/pm/PackageSignatures;Landroid/content/pm/PackageParser$Package;)I\n"
        "    .registers 16\n"
        "    const/4 v0, 0x0\n"
        "    return v0\n"
        ".end method",
    ),
    (
        r"\.method private compareSignaturesRecover\(Lcom/android/server/pm/PackageSignatures;Landroid/content/pm/PackageParser\$Package;\)I"
        r".*?\n\.end method",
        ".method private compareSignaturesRecover(Lcom/android/server/pm/PackageSignatures;Landroid/content/pm/PackageParser$Package;)I\n"
        "    .registers 16\n"
        "    const/4 v0, 0x0\n"
        "    return v0\n"
        ".end method",
    ),
]
for pat, repl in replacements:
    text, c = re.subn(pat, repl, text, count=1, flags=re.S)
    if c != 1:
        raise SystemExit(f"patch fail count={c} for {pat[:60]}")
open(path, "w", encoding="utf-8").write(text)
print("patched compareSignatures* (3 methods) → always SIGNATURE_MATCH")
PY

echo "=== smali assemble ==="
docker run --rm \
  -v "$WORKDIR:/work" \
  "$DOCKER_IMG" \
  smali assemble -a 24 -o /work/classes.dex /work/smali

[[ -s "$DEX" ]] || { echo "пустой classes.dex"; exit 1; }

echo "=== services.jar + classes.dex ==="
cp -f "$FW/services.jar" "$OUT"
# jar может быть без zip-структуры для обновления — python zipfile
python3 - "$OUT" "$DEX" <<'PY'
import zipfile, sys, os
jar, dex = sys.argv[1], sys.argv[2]
# пересобираем: манифест из исходного + classes.dex
src = zipfile.ZipFile(jar, "r")
names = src.namelist()
buf = {n: src.read(n) for n in names if n != "classes.dex"}
src.close()
tmp = jar + ".tmp"
with zipfile.ZipFile(tmp, "w", compression=zipfile.ZIP_DEFLATED) as z:
    for n, data in buf.items():
        z.writestr(n, data)
    z.write(dex, "classes.dex")
os.replace(tmp, jar)
print("jar:", jar, "dex:", os.path.getsize(dex))
PY

ls -lh "$OUT"
echo "OK: $OUT"
echo "В образ: заменить /framework/services.jar и удалить /framework/oat/arm/services.odex"
