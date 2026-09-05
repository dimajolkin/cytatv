# macOS — настройка

## Инструменты

```bash
brew install android-platform-tools picocom e2fsprogs
chmod +x scripts/*.sh
```

| Инструмент | Назначение |
|------------|------------|
| `picocom` не нужен | UART: `q22e uart` |
| `diskutil` + `dd` | SD с Ubuntu chroot |
| `e2fsprogs` (`debugfs`) | сборка `system.img` |
| `adb` | после custom (tcp `:5555`) |
| [eMMC153-Writer](https://github.com/dimajolkin/eMMC153-Writer) | ISP Socket |

## UART

```bash
go run ./cmd/q22e uart
```

[uart.md](uart.md).

## Прошивка

Только **ISP eMMC** + SD/USB для Linux: [flash.md](flash.md).

```bash
go run ./cmd/q22e android-oem-hack build
go run ./cmd/q22e android-oem-hack flash -d diskN --force
# sudo запросится в процессе (как ubuntu flash)
go run ./cmd/q22e ubuntu build
go run ./cmd/q22e ubuntu flash -d diskM --force
```

Raw `/dev/rdisk*` — из **Terminal.app** с Full Disk Access + sudo.
