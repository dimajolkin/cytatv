#!/usr/bin/env bash
# Перепаковка e2d rootfs → ext4 без 64bit/metadata_csum/flex_bg
# (Cyta Android kernel не монтирует оригинальный образ: features 0x2c4 + битый journal).
#
# Вход:  firmware/e2d/sd/e2d-armhf-pixel.img  (целый диск с MBR)
# Выход: firmware/e2d/sd/e2d-android-chroot.img  (тот же layout, совместимый FS)
#
# Нужен Docker. Запись на SD: YES=1 DISK=diskN ./scripts/prepare-sdcard.sh firmware/e2d/sd/e2d-android-chroot.img
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${1:-$ROOT/firmware/e2d/sd/e2d-armhf-pixel.img}"
OUT="${2:-$ROOT/firmware/e2d/sd/e2d-android-chroot.img}"
WORK="$ROOT/firmware/e2d/sd-work"
PART="$WORK/e2d-part.img"
NEWPART="$WORK/e2d-part-android.img"

[[ -f "$SRC" ]] || { echo "нет $SRC"; exit 1; }
command -v docker >/dev/null || { echo "нужен docker"; exit 1; }
E2FS="${E2FS:-/opt/homebrew/opt/e2fsprogs/sbin}"
[[ -x "$E2FS/e2fsck" ]] || { echo "brew install e2fsprogs"; exit 1; }

mkdir -p "$WORK"

echo "=== 1) partition из образа @1MiB ==="
if [[ ! -f "$PART" ]] || [[ "$SRC" -nt "$PART" ]]; then
  dd if="$SRC" of="$PART" bs=1m skip=1 status=progress
fi

echo "=== 2) e2fsck (journal / bitmaps) ==="
"$E2FS/e2fsck" -fy "$PART" || true

echo "=== 3) Docker: mkfs совместимый + rsync ==="
# Размер как у исходного раздела
SIZE=$(wc -c <"$PART" | tr -d ' ')
rm -f "$NEWPART"
dd if=/dev/zero of="$NEWPART" bs=1m count=$((SIZE / 1048576)) status=none
# добиваем хвост если SIZE не кратен 1MiB
python3 - <<PY
import os
p="$NEWPART"
want=$SIZE
cur=os.path.getsize(p)
if cur<want:
    with open(p,"ab") as f: f.truncate(want)
elif cur>want:
    os.truncate(p, want)
print("newpart", os.path.getsize(p))
PY

docker run --rm --privileged \
  -v "$PART:/in.img:ro" \
  -v "$NEWPART:/out.img" \
  ubuntu:22.04 bash -c '
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq e2fsprogs rsync >/dev/null
mkdir -p /mnt/in /mnt/out
# features: без 64bit / metadata_csum / flex_bg / huge_file
mkfs.ext4 -F -b 4096 -I 256 -L e2d-android \
  -O extent,filetype,sparse_super,dir_index,resize_inode,has_journal,ext_attr,^64bit,^metadata_csum,^flex_bg,^huge_file,^ea_inode,^encrypt,^metadata_csum_seed \
  /out.img
mount -o loop,ro /in.img /mnt/in
mount -o loop /out.img /mnt/out
rsync -aHAX --numeric-ids /mnt/in/ /mnt/out/
# маркер для cytatv-sd-linux.sh
echo "android-chroot" >/mnt/out/etc/cytatv-sd-linux
test -f /mnt/out/etc/debian_version
cat /mnt/out/etc/debian_version
sync
umount /mnt/out
umount /mnt/in
e2fsck -fy /out.img
dumpe2fs -h /out.img | grep -E "features|state|Block count|64bit|Checksum type" || true
'

echo "=== 4) собрать disk image (MBR + part @1MiB) ==="
# копируем MBR/gap из исходника, подставляем новый раздел
cp -f "$SRC" "$OUT"
python3 - <<PY
import shutil
src_part="$NEWPART"
out="$OUT"
part=open(src_part,"rb").read()
with open(out,"r+b") as f:
    f.seek(1024*1024)
    f.write(part)
    # обрезать до MBR+part (как у исходника)
    f.truncate(1024*1024 + len(part))
print("out", out, 1024*1024+len(part))
PY

echo "=== 5) проверка раздела ==="
E2FS="${E2FS:-/opt/homebrew/opt/e2fsprogs/sbin}"
"$E2FS/dumpe2fs" -h "$NEWPART" 2>&1 | grep -E 'Filesystem features|Filesystem state'
"$E2FS/debugfs" -R 'cat /etc/debian_version' "$NEWPART" 2>&1 | grep -v '^debugfs' || true
"$E2FS/debugfs" -R 'cat /etc/cytatv-sd-linux' "$NEWPART" 2>&1 | grep -v '^debugfs' || true

ln -sfn "$(basename "$OUT")" "$(dirname "$OUT")/linux-android.img"

echo ""
echo "Готово: $OUT"
echo "Запись: YES=1 DISK=diskN sudo -E $ROOT/scripts/prepare-sdcard.sh $OUT"
echo "(Built-in reader часто disk11)"
