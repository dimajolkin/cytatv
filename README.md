# cytatv

TV-приставка **Cyta** (Huawei Q22E-E1301, Hi3798CV200) — дамп, custom Android, Ubuntu chroot.  
Рабочая среда: **macOS** + ISP eMMC153.

## Статус

| | |
|---|---|
| UART | ✅ boot log @ 115200, **только чтение** |
| Прошивка | ✅ **ISP eMMC** ([docs/flash.md](docs/flash.md)) |
| Backup | ✅ `build/original/` (`q22e init`) |
| Custom Android | OpenLauncher HOME, q22esu, Magisk, SSH, ADB tcp → `android-oem-hack` |
| Linux | Ubuntu Base armhf chroot — [ubuntu-chroot.md](docs/ubuntu-chroot.md) |

MENU / `.upk` / синяя кнопка на этой Cyta **недоступны** (ADVCA).

## Быстрый путь

```bash
# 0) один раз: ISP-дамп + SSH-ключи
mkdir -p build/original
# original.img (dd с Socket) или original.dmg (сырой дамп с ридера)
go run ./cmd/q22e init
go run ./cmd/q22e keys

# 1) android-oem-hack → Socket
go run ./cmd/q22e android-oem-hack build
go run ./cmd/q22e android-oem-hack flash -d diskN --force --verify
# diskN = Socket ~7.8G; sudo в процессе; Terminal.app + Full Disk Access

# 2) Ubuntu на SD/USB (опционально)
go run ./cmd/q22e ubuntu build
go run ./cmd/q22e ubuntu flash -d diskM --force

# 3) чип в плату → 12V → UART
go run ./cmd/q22e uart
# без носителя → Android + SSH/ADB/su
# с Ubuntu SD/USB → SSH :22 в Ubuntu (root)
```

CLI: `init` · `keys` · `android-oem-hack` · `ubuntu` · `uart` · `list` · `wizard`

## Документация

| Файл | |
|------|--|
| **[docs/flash.md](docs/flash.md)** | ISP → Android + чеклист |
| [docs/firmware-backup.md](docs/firmware-backup.md) | дамп `build/original/` |
| [docs/ubuntu-chroot.md](docs/ubuntu-chroot.md) | Ubuntu Base armhf + chroot |
| [docs/emmc-isp.md](docs/emmc-isp.md) | пины, оффсеты |
| [docs/uart.md](docs/uart.md) | UART |
| [docs/macos-setup.md](docs/macos-setup.md) | brew / порты |
| [docs/README.md](docs/README.md) | индекс |

## Структура

```
configs/                    # YAML + emmc_partitions_q22e.xml
assets/logo/                # splash JPEG
assets/ssh/                 # локально: q22e keys (.keep в git)
build/original/             # original.img|.dmg → partitions/ + filesystems/
build/android-oem-hack/     # образы + скачанные assets/
build/ubuntu/               # Ubuntu chroot image
cmd/q22e/                   # CLI
internal/{cli,config,oemhack,original,ubuntu}/
docs/
```

Вне репо: [eMMC153-Writer](https://github.com/dimajolkin/eMMC153-Writer).
