# macOS — настройка

## Инструменты

```bash
brew install android-platform-tools picocom e2fsprogs
chmod +x scripts/*.sh
```

| Инструмент | Назначение |
|------------|------------|
| `picocom` / `screen` | UART boot log |
| `diskutil` + `dd` | SD с e2d |
| `e2fsprogs` (`debugfs`) | сборка `system.img` |
| `adb` | после custom (tcp `:5555`) |
| [eMMC153-Writer](https://github.com/dimajolkin/eMMC153-Writer) | ISP Socket |

## UART

```bash
./scripts/uart-capture.sh
```

[uart.md](uart.md).

## Прошивка

Только **ISP eMMC** + SD/USB для Linux: [flash.md](flash.md).

```bash
./scripts/build-custom-android.sh
./scripts/flash-custom-emmc.sh   # YES=1 DISK=diskN sudo -E …
./scripts/build-e2d.sh
./scripts/prepare-sdcard.sh firmware/e2d/sd/e2d-armhf-pixel.img
./scripts/prepare-e2d-usb.sh /Volumes/USB menu
```

Raw `/dev/rdisk*` — из **Terminal.app** с Full Disk Access + sudo.
