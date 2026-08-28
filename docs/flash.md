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
        ├── без SD: «чистый» Android
        │
        ▼
  microSD e2d вставлена → init: cytatv-sd-linux.sh → chroot Debian
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
| `system.img` | 1886M / 1200M (живой ext4, debloat + root + SD Linux) |

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

## 3. Linux с microSD

Образ уже на SD — см. [linux-install.md](linux-install.md).  
После boot Android init сам монтирует e2d и поднимает chroot (если SD на месте).

Отключить автозапуск: `setprop persist.cytatv.sdlinux 0`.

## Чеклист после прошивки

1. SD с e2d вставлена (если нужен Linux).
2. Чип в плату → 12V.
3. UART: `./scripts/uart-capture.sh`
   - `cytatv init.bigfish.sh` / hooks
   - при SD: `cytatv: sd-linux started`
4. Сеть → SSH: `ssh -i firmware/custom/assets/ssh/id_ed25519_q22e root@<IP>`
5. `su -c id` → `uid=0`
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
