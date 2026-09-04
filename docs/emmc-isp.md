# eMMC153 ISP — пины и запись

**Основной способ** прошивки этой Q22E (UART read-only). Обзор: [flash.md](flash.md).

## Минимум линий (1-bit)

| Сигнал | Шар | |
|--------|-----|--|
| **CLK** | **M6** | |
| **CMD** | **M5** | pull-up 10–47kΩ → VCCQ |
| **DAT0** | **A3** | pull-up 10–47kΩ → VCCQ |
| **VCC** | **E6** | 3.3V (или F5/J10/K9) |
| **VCCQ** | **M4** | 1.8 или 3.3V — замерить |
| **GND** | **A6** | или плоскость VSS |

**Ориентация на плате:** A1 — верхний левый (вырез шёлка). Правый нижний *видимый* пад матрицы часто **P6** (P7–P14 в JEDEC — NC).

Фото: [`photos/`](photos/README.md) (`13`–`16`, `22`, `23`).

На плате (чип на месте): паять к via — [`photos/23-emmc-pcb-isp-via-annotated.png`](photos/23-emmc-pcb-isp-via-annotated.png). Pull-up уже на плате; минимум: **CLK, CMD, DAT0, GND** (+ питание платы).

Для серийной записи (~80 плат): **сокет eMMC153**, не паять ISP на каждую.

## Запись generic Android

Источник образов: **`build/android-oem-hack/`**. Оффсеты — из `configs/emmc_partitions_q22e.xml` / [inventory.md](inventory.md):

| Раздел | Offset | Length слота | Файл |
|--------|--------|--------------|------|
| logo | 77 MiB | 16 MiB | `logo.img` (8 MiB) |
| kernel | 141 MiB | 15 MiB | `kernel.img` (12 MiB) |
| system | 1886 MiB | 1200 MiB | `system.img` (800 MiB) |

Байты (MiB = 1024²):

```
logo:   skip=77M   seek=77M
kernel: skip=141M  seek=141M
system: skip=1886M seek=1886M
```

**Mac CLI:** [eMMC153-Writer](https://github.com/dimajolkin/eMMC153-Writer) → `eMMC153-Worker batch`

```bash
# Terminal.app + sudo (Full Disk Access)
cd ~/Project/Github/eMMC153-Writer
go build -o eMMC153-Worker ./cmd/worker
diskutil list   # Socket ~7.8 GB → rdiskN
sudo ./eMMC153-Worker batch \
  --device /dev/rdiskN \
  --android ~/Project/Github/cytatv/build/android-oem-hack \
  --verify
```

CLI: `sudo go run ./cmd/q22e android-oem-hack flash -d diskN --force`  
Из агента/osascript raw `/dev/rdisk*` → часто `Operation not permitted`.

Откат Cyta — те же оффсеты, файлы из `build/original/partitions/`.

Полный образ: `build/original/original.img` (или `.dmg`) → целиком на чип.
