# Прошивка Q22E — актуальный путь

Для этой Cyta: UART read-only на стоке → **только ISP eMMC**.  
Verified boot (ADVCA) не ломаем: родные `bootargs` / `kernel`.

```
firmware/cyta/ (бэкап ✅)
        │
        ▼
  ISP: firmware/custom (logo + kernel + system)
        │
        ▼
  Custom Android + Magisk system-root + SSH/ADB
        │
        ├── без носителя: «чистый» Android
        │
        ▼
  SD/USB e2d → cytatv-sd-linux.sh → Debian SSH :22 (root) + Enigma2
```

## 1. Бэкап

Уже есть: [firmware-backup.md](firmware-backup.md) → каталог `firmware/cyta/`.

Перед любой записью: чип в сокете / полный образ сохранён.

## 2. Custom Android (из Cyta, без IPTV)

Файлы в **`firmware/custom/`** (сборка: `./scripts/build-custom-android.sh`):

| Файл | Слот |
|------|------|
| `logo.img` | 77M / 16M |
| `kernel.img` | 141M / 15M |
| `system.img` | 1886M / 1200M (живой ext4, debloat + root + SD/USB Linux) |

```bash
./scripts/build-custom-android.sh

YES=1 DISK=diskN sudo -E ./scripts/flash-custom-emmc.sh
```

Или вручную:

```bash
cd ../eMMC153-Writer && go build -o eMMC153-Worker ./cmd/worker
sudo ./eMMC153-Worker batch \
  --device /dev/rdiskN \
  --android ~/Project/Github/cytatv/firmware/custom \
  --verify
```

`rdiskN` = Socket ~7.8 GB (`diskutil list`). Только **Terminal.app + sudo**.

Откат к стоку: `firmware/cyta/`.  
**Обязательно** wipe **userdata** в batch (старый HOME / Cyta).

## 3. Linux с SD/USB

Образ: `e2d-android-chroot.img` — [linux-install.md](linux-install.md).  
После boot init монтирует e2d, отдаёт **SSH :22 root** и пытается запустить **Enigma2**.

Отключить: `setprop persist.cytatv.sdlinux 0`.

## Чеклист после прошивки

1. SD или USB с e2d вставлена (ehci для USB).
2. Чип в плату → 12V.
3. UART: `./scripts/uart-capture.sh`
   - `cytatv init.bigfish.sh` / hooks
   - при носителе: `sd-linux started` → `sshd ok :22 (root)` → `enigma2 ok|fail`
4. Сеть → SSH в Debian: `ssh -i firmware/custom/assets/ssh/id_ed25519_q22e root@<IP>`
5. Без носителя: `su -c id` → `uid=0` (Android)
6. ADB: `adb connect <IP>:5555`
7. Ручной повтор: `/system/xbin/cytatv-sd-linux.sh`

## Что не работает на этой приставке

| Метод | Почему |
|-------|--------|
| HiTool / burn по UART | RX на плате не принимает ввод |
| Recovery «Apply update» | только подписанный Cyta `update.zip` |
| e2d `.upk` / MENU / синяя кнопка | ADVCA; без OEM private key — [experiments/advca-boot/](../experiments/advca-boot/) |
| Правка `bootargs` / hybrid env | RSA → boot loop |
| ADB на стоковой Cyta | debugging вырезан (на custom — tcp 5555) |
