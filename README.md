# cytatv

TV-приставка **Cyta** (Huawei Q22E-E1301, Hi3798CV200) — дамп, custom Android, Debian e2d.  
Рабочая среда: **macOS** + ISP eMMC153.

## Статус

| | |
|---|---|
| UART | ✅ boot log @ 115200, **только чтение** |
| Прошивка | ✅ **ISP eMMC** ([docs/flash.md](docs/flash.md)) |
| Backup | ✅ `firmware/cyta/` |
| Custom Android | Lawnchair, cytasu, Q22E Settings, Magisk app, SSH, ADB tcp, extras |
| Linux e2d | SD/USB → **SSH root + Enigma2** после boot ([linux-install.md](docs/linux-install.md)) |

MENU / `.upk` / синяя кнопка на этой Cyta **недоступны** (ADVCA) — см. [experiments/advca-boot/](experiments/advca-boot/).

## Быстрый путь

```bash
# 1) Custom Android (Lawnchair + cytasu + Q22E Settings + bash)
./scripts/build-custom-android.sh
# или со сборкой прямо перед прошивкой:
# YES=1 BUILD=1 DISK=diskN sudo -E ./scripts/flash-custom-emmc.sh
YES=1 DISK=diskN sudo -E ./scripts/flash-custom-emmc.sh
# diskN = Socket ~7.8G (diskutil list), только Terminal.app + sudo

# 2) SD или USB с e2d-android-chroot — вставить до cold boot
# YES=1 DISK=diskM sudo -E ./scripts/prepare-sdcard.sh firmware/e2d/sd/e2d-android-chroot.img

# 3) чип в плату → 12V → UART
./scripts/uart-capture.sh
# без носителя → Android + SSH/ADB/su
# с SD/USB    → Debian SSH :22 (root) + Enigma2 на HDMI
```

## Документация

| Файл | |
|------|--|
| **[docs/flash.md](docs/flash.md)** | ISP → Android + чеклист |
| [docs/linux-install.md](docs/linux-install.md) | SD/USB e2d + SSH + Enigma2 |
| [docs/emmc-isp.md](docs/emmc-isp.md) | пины, оффсеты |
| [docs/uart.md](docs/uart.md) | UART |
| [docs/macos-setup.md](docs/macos-setup.md) | brew / порты |
| [docs/README.md](docs/README.md) | индекс |
| [experiments/advca-boot/](experiments/advca-boot/) | ISP/ADVCA boot-эксперименты |

## Структура

```
firmware/cyta/       # дамп Cyta
firmware/custom/     # custom Android (сборка)
firmware/e2d/        # Debian e2d (сборка)
firmware/flash/      # исходники e2d
scripts/             # macOS-скрипты
experiments/         # ISP/boot lab (не основной flash-путь)
docs/
```

Вне репо: [eMMC153-Writer](https://github.com/dimajolkin/eMMC153-Writer) → `eMMC153-Worker`.
