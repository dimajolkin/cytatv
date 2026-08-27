#!/usr/bin/env bash
# firmware/e2d — отдельная сборка Debian e2d (Hi3798CV200), не Android custom.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/firmware/flash"
OUT="$ROOT/firmware/e2d"

UPK_PREF="e2d-armhf-pixel-20210226_K3.18.24.upk"
UPK_ALT="e2d-armhf-pixel-20210226_K4.4.35.upk"
IMG="e2d-armhf-pixel.img"

need() {
  local f="$1"
  [[ -f "$SRC/$f" ]] || {
    echo "нет $SRC/$f"
    echo "Скачай: ./scripts/download-e2d.sh"
    echo "  и при необходимости: cd firmware/flash && tar xjf e2d-armhf-pixel.img_20210226.tar.bz2"
    exit 1
  }
}

need "$UPK_PREF"
need "$UPK_ALT"
need "$IMG"
[[ -f "$SRC/ChangeLog.md" ]] || echo "WARN: нет ChangeLog.md"

# clonefile на APFS (без удвоения 3.7G), иначе hardlink, иначе cp
link_or_copy() {
  local src="$1" dst="$2"
  rm -f "$dst"
  if cp -c "$src" "$dst" 2>/dev/null; then
    echo "clone: $(basename "$dst")"
  elif ln "$src" "$dst" 2>/dev/null; then
    echo "hardlink: $(basename "$dst")"
  else
    echo "copy: $(basename "$dst") (медленно)…"
    cp -f "$src" "$dst"
  fi
}

echo "=== firmware/e2d build ==="
rm -rf "$OUT"
mkdir -p "$OUT/usb" "$OUT/sd"

link_or_copy "$SRC/$UPK_PREF" "$OUT/usb/$UPK_PREF"
link_or_copy "$SRC/$UPK_ALT" "$OUT/usb/$UPK_ALT"
# USB update path (MENU → зелёная): img в корень флешки
link_or_copy "$SRC/$IMG" "$OUT/usb/$IMG"
link_or_copy "$SRC/$IMG" "$OUT/sd/$IMG"
[[ -f "$SRC/ChangeLog.md" ]] && cp -f "$SRC/ChangeLog.md" "$OUT/ChangeLog.md"

# удобные имена без даты
ln -sf "$UPK_PREF" "$OUT/usb/menu.upk"
ln -sf "$IMG" "$OUT/usb/linux.img"
ln -sf "$IMG" "$OUT/sd/linux.img"

cat > "$OUT/usb/README.txt" <<'EOF'
FAT32 USB → корень флешки:

  1) MENU (после custom Android):
       e2d-armhf-pixel-20210226_K3.18.24.upk
     (или menu.upk)

  2) Linux без microSD (MENU → зелёная → UPDT):
       e2d-armhf-pixel.img  (+ при необходимости update.img / update.upk с зеркала)

Рабочий USB-порт на Q22E: ehci (не порт с error -71).
EOF

cat > "$OUT/README.md" <<'EOF'
# firmware/e2d — Debian Linux (сборка)

Отдельно от Android (`firmware/custom`).  
Источник образов: `firmware/flash/` (скачивание `./scripts/download-e2d.sh`).

| Путь | Назначение |
|------|------------|
| `usb/` | FAT32-флешка: `.upk` (MENU) + `.img` (update) |
| `sd/` | запись на microSD → синяя кнопка |

## Предусловие

На eMMC уже **custom Android** (не операторская Cyta):

```bash
./scripts/build-custom-android.sh
# ISP: eMMC153-Worker … --android firmware/custom
```

## 1. MENU (.upk)

```bash
# флешка FAT32 смонтирована, например /Volumes/USB
./scripts/prepare-e2d-usb.sh /Volumes/USB
```

На приставке: local update / file manager → поставить `.upk` → reboot → экран **MENU**.

| Пульт | |
|-------|--|
| Красная | Android |
| Зелёная | USB update → internal |
| **Синяя** | **Linux** (нужна SD с образом или уже залитый update) |

## 2. microSD

```bash
./scripts/prepare-sdcard.sh firmware/e2d/sd/e2d-armhf-pixel.img
# или неинтерактивно:
YES=1 DISK=diskN ./scripts/prepare-sdcard.sh firmware/e2d/sd/e2d-armhf-pixel.img
```

SD в STB → MENU → **синяя**.

## 3. После boot

```bash
ssh root@<IP>
```

Подробнее: [docs/linux-install.md](../../docs/linux-install.md).
EOF

cat > "$OUT/MANIFEST.txt" <<EOF
e2d: Debian 10 + Enigma2 (Hi3798CV200 armhf pixel)
built: $(date -u +%Y-%m-%dT%H:%M:%SZ)
source: firmware/flash/
usb/$UPK_PREF  $(wc -c <"$OUT/usb/$UPK_PREF" | tr -d ' ')
usb/$UPK_ALT   $(wc -c <"$OUT/usb/$UPK_ALT" | tr -d ' ')
usb/$IMG       $(wc -c <"$OUT/usb/$IMG" | tr -d ' ')
sd/$IMG        $(wc -c <"$OUT/sd/$IMG" | tr -d ' ')
menu: K3.18.24 preferred; K4.4.35 fallback
after: custom Android on eMMC → .upk MENU → SD/USB Linux
rebuild: ./scripts/build-e2d.sh
docs: docs/linux-install.md
EOF

echo ""
echo "Done: $OUT"
cat "$OUT/MANIFEST.txt"
echo ""
du -sh "$OUT" "$OUT/usb" "$OUT/sd" 2>/dev/null || true
ls -lh "$OUT/usb" "$OUT/sd"
