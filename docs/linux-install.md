# Linux (Debian e2d) на Cyta — через SD + chroot

**Цель:** Debian с microSD поверх custom Android (тот же Cyta kernel).  
**Предусловие:** eMMC с custom Android — [flash.md](flash.md).

На этой операторской Cyta **нельзя** получить e2d MENU / синюю кнопку (ADVCA).  
Рабочий путь: Android boot → детект SD → mount → **chroot** (автозапуск).

Сборка образов (если нужно перезаписать SD): `firmware/e2d/` ← `./scripts/build-e2d.sh`.

---

## Файлы

| Путь | Назначение |
|------|------------|
| `firmware/e2d/sd/*.img` | запись на microSD |
| `/system/xbin/cytatv-sd-linux.sh` | mount + chroot + getty/sshd (в custom Android) |

`firmware/e2d/usb/*.upk` — только для **generic** Q22 без ADVCA Cyta; на этой приставке не использовать как основной путь.

---

## 1. microSD (совместимый с Android kernel)

Оригинальный `e2d-armhf-pixel.img` Cyta **не монтирует** (`64bit` / битый journal).  
Нужен перепакованный образ:

```bash
./scripts/repack-e2d-for-android.sh
YES=1 DISK=diskM sudo -E ./scripts/prepare-sdcard.sh firmware/e2d/sd/e2d-android-chroot.img
```

Вставить SD **до** cold boot (или перезагрузить после вставки).

---

## 2. Автозапуск

После `sys.boot_completed` (и из `cytatv-boot.sh`):

1. Ждёт блок SD (`mmcblk1` / `mmcblk1p1`, до ~60 с).
2. Mount → `/mnt/linux`.
3. Проверяет e2d (`/etc/debian_version`).
4. Bind `proc` / `sys` / `dev` / `dev/pts`.
5. В chroot: sshd/dropbear (если есть) + login/getty на `ttyAMA0`.

Лог на UART: `cytatv: sd-linux started` или `cytatv: sd-linux skip (no sd)`.

| Prop | |
|------|--|
| `persist.cytatv.sdlinux=1` | автозапуск (по умолчанию) |
| `persist.cytatv.sdlinux=0` | только Android |

Ручной запуск: `/system/xbin/cytatv-sd-linux.sh`

Это **не** нативный boot e2d kernel / полноценный Enigma2 через MENU — userspace Debian на Android kernel.

---

## 3. После входа в Debian

```bash
# из Android (SSH :22):
chroot /mnt/linux /bin/bash
# или второй SSH, если в chroot подняли sshd на другом порту / после stop dropbear
```

Kodi вместо Enigma2 (внутри e2d, если systemd в chroot ограничен — может не подойти):

```bash
systemctl disable enigma2
systemctl enable kodi
```

---

## Generic Q22 (не эта Cyta): MENU / `.upk`

На приставках **без** ADVCA Cyta путь e2d MENU ещё возможен:

```bash
./scripts/prepare-e2d-usb.sh /Volumes/USB menu
# reboot → MENU → синяя = Linux
```

На нашей Cyta это закрыто — см. [experiments/advca-boot/](../experiments/advca-boot/).

---

## Статус

- [x] UART / inventory / backup
- [x] Сборка `firmware/e2d/`
- [x] Custom Android + root + `cytatv-sd-linux` autostart
- [ ] ISP flash свежего custom + smoke на железе
