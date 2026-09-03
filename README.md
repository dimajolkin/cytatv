# cytatv

TV-приставка **Cyta** (Huawei Q22E-E1301, Hi3798CV200) — дамп, custom Android, Debian e2d.  
Рабочая среда: **macOS** + ISP eMMC153.

## Статус

| | |
|---|---|
| UART | ✅ boot log @ 115200, **только чтение** |
| Прошивка | ✅ **ISP eMMC** ([docs/flash.md](docs/flash.md)) |
| Backup | ✅ `firmware/cyta/` |
| Custom Android | Lawnchair, cytasu root, Magisk app, SSH, ADB tcp, extras |
| Linux e2d | microSD → **автозапуск chroot** после boot Android ([linux-install.md](docs/linux-install.md)) |

MENU / `.upk` / синяя кнопка на этой Cyta **недоступны** (ADVCA) — см. [experiments/advca-boot/](experiments/advca-boot/).

## Быстрый путь

```bash
# 1) Custom Android (root + SD Linux autostart)
./scripts/build-custom-android.sh
YES=1 DISK=diskN sudo -E ./scripts/flash-custom-emmc.sh
# diskN = Socket ~7.8G (diskutil list), только Terminal.app + sudo

# 2) microSD уже с e2d — вставить до cold boot
# при необходимости перезаписать:
# YES=1 DISK=diskM sudo -E ./scripts/prepare-sdcard.sh firmware/e2d/sd/e2d-armhf-pixel.img

# 3) чип в плату → 12V → UART
./scripts/uart-capture.sh
# без SD → Android + SSH/ADB/su
# с SD   → mount e2d + chroot (getty UART / sshd)
```

## Документация

| Файл | |
|------|--|
| **[docs/flash.md](docs/flash.md)** | ISP → Android + чеклист |
| [docs/linux-install.md](docs/linux-install.md) | SD e2d + автозапуск |
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
