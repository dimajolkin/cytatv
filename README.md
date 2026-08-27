# cytatv

TV-приставка **Cyta** (Huawei Q22E-E1301, Hi3798CV200) — дамп, custom Android, Debian e2d.  
Рабочая среда: **macOS** + ISP eMMC153.

## Статус

| | |
|---|---|
| UART | ✅ boot log @ 115200, **только чтение** |
| Прошивка | ✅ **ISP eMMC** ([docs/flash.md](docs/flash.md)) |
| Backup | ✅ `firmware/cyta/` |
| Custom Android | Lawnchair, root, SSH, Amaze, TermOnePlus, Lightning |
| Linux e2d | `firmware/e2d/` после custom |

## Быстрый путь

```bash
# 1) Custom Android
./scripts/build-custom-android.sh
cd ../eMMC153-Writer
sudo ./eMMC153-Worker batch \
  --device /dev/rdiskN \
  --android ~/Project/Github/cytatv/firmware/custom \
  --verify
# rdiskN = Socket ~7.8G (diskutil list), только Terminal.app + sudo

# 2) Debian на SD
./scripts/build-e2d.sh
YES=1 DISK=diskM sudo -E ./scripts/prepare-sdcard.sh firmware/e2d/sd/e2d-armhf-pixel.img

# 3) .upk → MENU (FAT USB), затем MENU → синяя = Linux
./scripts/prepare-e2d-usb.sh /Volumes/USB menu
```

## Документация

| Файл | |
|------|--|
| **[docs/flash.md](docs/flash.md)** | ISP → Android / Linux |
| [docs/emmc-isp.md](docs/emmc-isp.md) | пины, оффсеты |
| [docs/linux-install.md](docs/linux-install.md) | e2d |
| [docs/uart.md](docs/uart.md) | UART |
| [docs/macos-setup.md](docs/macos-setup.md) | brew / порты |
| [docs/README.md](docs/README.md) | индекс |

## Структура

```
firmware/cyta/       # дамп Cyta
firmware/custom/     # custom Android (сборка)
firmware/e2d/        # Debian e2d (сборка)
firmware/flash/      # исходники e2d
scripts/             # macOS-скрипты
docs/
```

Вне репо: [eMMC153-Writer](https://github.com/dimajolkin/eMMC153-Writer) → `eMMC153-Worker`.
