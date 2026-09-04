# Ubuntu Base на Cyta (chroot)

**Цель:** свежий Ubuntu armhf на SD/USB → после boot Android: **SSH root в Ubuntu**.  
**Не** нативный Ubuntu kernel (ADVCA). e2d — legacy, см. [linux-install.md](linux-install.md).

Источник: [Ubuntu Base 24.04 armhf](https://cdimage.ubuntu.com/ubuntu-base/releases/24.04/release/).

---

## Сборка и запись

```bash
go run ./cmd/q22e ubuntu build
go run ./cmd/q22e ubuntu flash -d diskN --force
```

| Путь | |
|------|--|
| `build/ubuntu/ubuntu-chroot.img` | образ для dd |
| `build/ubuntu/dl/` | скачанный tar.gz |
| `/system/xbin/cytatv-sd-linux.sh` | автозапуск chroot |

---

## Автозапуск

После `sys.boot_completed` (prop `persist.cytatv.sdlinux=1`):

1. SD (`mmcblk1`) или USB (`sda`) с `/etc/debian_version` / Ubuntu.
2. Smoke: `chroot /bin/sh` — иначе Android UI **не** гасится.
3. SSH Debian/Ubuntu `:22` (Android dropbear останавливается).
4. UI handoff (zygote off) только если `persist.cytatv.sdlinux.ui=1` (по умолчанию **нет**).

```bash
ssh -i firmware/custom/assets/ssh/id_ed25519_q22e root@<IP>
```

Отключить: `setprop persist.cytatv.sdlinux 0` + reboot.

---

## Статус

- [x] Пайплайн Ubuntu Base → img
- [ ] Smoke на железе (SSH)
