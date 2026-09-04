# cytatv

TV-приставка **Cyta** (Huawei Q22E-E1301, Hi3798CV200) — дамп, custom Android, Debian e2d.  
Рабочая среда: **macOS** + ISP eMMC153.

## Статус

| | |
|---|---|
| UART | ✅ boot log @ 115200, **только чтение** |
| Прошивка | ✅ **ISP eMMC** ([docs/flash.md](docs/flash.md)) |
| Backup | ✅ `firmware/cyta/` |
| Custom Android | Lawnchair, cytasu, Q22E Settings, Magisk app, SSH, ADB tcp, extras → `android-oem-hack` |
| Linux | Ubuntu Base armhf chroot — [ubuntu-chroot.md](docs/ubuntu-chroot.md) (e2d legacy: [linux-install.md](docs/linux-install.md)) |

MENU / `.upk` / синяя кнопка на этой Cyta **недоступны** (ADVCA) — см. [experiments/advca-boot/](experiments/advca-boot/).

## Быстрый путь

```bash
# 1) android-oem-hack
go run ./cmd/q22e android-oem-hack build
sudo go run ./cmd/q22e android-oem-hack flash -d diskN --force
# diskN = Socket ~7.8G, Terminal.app + sudo

# 2) Ubuntu на SD/USB
go run ./cmd/q22e ubuntu build
go run ./cmd/q22e ubuntu flash -d diskM --force

# 3) чип в плату → 12V → UART
go run ./cmd/q22e uart
# без носителя → Android + SSH/ADB/su
# с Ubuntu SD/USB → SSH :22 в Ubuntu (root), Android UI остаётся
```

## Документация

| Файл | |
|------|--|
| **[docs/flash.md](docs/flash.md)** | ISP → Android + чеклист |
| [docs/ubuntu-chroot.md](docs/ubuntu-chroot.md) | Ubuntu Base armhf + chroot |
| [docs/linux-install.md](docs/linux-install.md) | e2d legacy |
| [docs/emmc-isp.md](docs/emmc-isp.md) | пины, оффсеты |
| [docs/uart.md](docs/uart.md) | UART |
| [docs/macos-setup.md](docs/macos-setup.md) | brew / порты |
| [docs/README.md](docs/README.md) | индекс |
| [experiments/advca-boot/](experiments/advca-boot/) | ISP/ADVCA boot-эксперименты |

## Структура

```
firmware/cyta/              # дамп Cyta
firmware/custom/assets/     # seed для assets без url
build/android-oem-hack/     # образы + assets/ + src/settings
build/ubuntu/               # Ubuntu chroot image
firmware/ubuntu/            # legacy / промежуточные Ubuntu артефакты
firmware/e2d/               # Debian e2d (legacy)
firmware/flash/             # исходники e2d
scripts/
experiments/
docs/
```

Вне репо: [eMMC153-Writer](https://github.com/dimajolkin/eMMC153-Writer) → `eMMC153-Worker`.
