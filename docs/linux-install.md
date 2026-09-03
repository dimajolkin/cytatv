# Linux (Debian e2d) на Cyta — SD/USB + chroot

**Цель:** при вставленном носителе с e2d сразу **SSH в Debian (root)** и **UI Enigma2** на HDMI.  
Android на eMMC — только загрузка ядра/сети; MENU/синяя кнопка на этой Cyta недоступны (ADVCA).

**Образ:** `firmware/e2d/sd/e2d-android-chroot.img` (перепаковка `e2d-armhf-pixel`, без 64bit).  
Сборка: `./scripts/build-e2d.sh` → `./scripts/repack-e2d-for-android.sh`.

---

## Файлы

| Путь | Назначение |
|------|------------|
| `firmware/e2d/sd/e2d-android-chroot.img` | запись на microSD или USB |
| `/system/xbin/cytatv-sd-linux.sh` | mount + chroot root: SSH :22 + Enigma2 |

---

## 1. Запись носителя

```bash
./scripts/repack-e2d-for-android.sh   # если ещё нет android-chroot
YES=1 DISK=diskM sudo -E ./scripts/prepare-sdcard.sh firmware/e2d/sd/e2d-android-chroot.img
```

Вставить **до** cold boot (USB — ehci-порт). SD и USB равноправны.

---

## 2. Автозапуск (после `sys.boot_completed`)

1. Ищет Debian на SD (`mmcblk1`) затем USB (`sda`/`sdb`), только если есть `/etc/debian_version`.
2. Mount → `/mnt/linux`, bind `proc`/`sys`/`dev`.
3. Гасит Android dropbear; поднимает **sshd/dropbear Debian на :22** (uid 0).
4. Останавливает zygote/surfaceflinger; стартует **Enigma2 от root**.
5. Ключ SSH: тот же `assets/ssh/id_ed25519_q22e` (копируется в `/root/.ssh`).

| Prop | |
|------|--|
| `persist.cytatv.sdlinux=1` | автозапуск (по умолчанию) |
| `persist.cytatv.sdlinux=0` | только Android |

Ручной запуск: `/system/xbin/cytatv-sd-linux.sh`

UART: `cytatv: sd-linux started` → `sshd ok :22 (root)` → `enigma2 ok (uid0 root)` или `enigma2 fail …`.

Это userspace Debian на **Android kernel**, не нативный e2d boot. Если HDMI не взял Enigma2 — SSH в Linux всё равно должен работать.

---

## 3. Вход

```bash
ssh -i firmware/custom/assets/ssh/id_ed25519_q22e root@<IP>
# или с приставки:
chroot /mnt/linux /bin/bash
```

---

## Generic Q22 (не эта Cyta): MENU / `.upk`

```bash
./scripts/prepare-e2d-usb.sh /Volumes/USB menu
# reboot → MENU → синяя = Linux
```

На нашей Cyta закрыто — [experiments/advca-boot/](../experiments/advca-boot/).

---

## Статус

- [x] Custom Android + `cytatv-sd-linux` (SD/USB, SSH root, Enigma2 handoff)
- [ ] ISP flash + smoke на железе (SSH + HDMI)
