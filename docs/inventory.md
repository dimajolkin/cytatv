# Inventory — Cyta STB Q22E

Источники: `recovery-boot-log.txt` (2026-07-05), `boot-log.txt`, ISP-дамп `firmware/cyta/`.

## Подтверждено

| Параметр | Значение |
|----------|----------|
| Модель | Huawei Q22E-E1301 |
| SoC | Hi3798CV200 |
| RAM | **1961 MB (~2 GB)** (`mem=1961M`) |
| Flash | **eMMC**, полный образ ~**7.3 GB** |
| UART | ttyAMA0 **115200**, **read-only** |
| Boot | compressed-boot, Android |
| SELinux | `selinux=disabled` |
| Доступ | ISP ✅ · HiTool/ADB ❌ — см. [hardware.md](hardware.md) |

## Разделы eMMC (`blkdevparts`)

| # | Раздел | Размер | Start (накопительно) |
|---|--------|--------|----------------------|
| 1 | fbl | 1M | 0 |
| 2 | fbldata | 1M | 1M |
| 3 | trustedcore | 16M | 2M |
| 4 | trustedcorebak | 16M | 18M |
| 5 | fastboot | 2M | 34M |
| 6 | sblbak | 2M | 36M |
| 7 | bootargs | 4M | 38M |
| 8 | recovery | 30M | 42M |
| 9 | deviceinfo | 1M | 72M |
| 10 | baseparam | 4M | 73M |
| 11 | **logo** | **16M** | **77M** |
| 12 | fastplay | 16M | 93M |
| 13 | misc | 8M | 109M |
| 14 | factory | 24M | 117M |
| 15 | **kernel** | **15M** | **141M** |
| 16 | cadata | 10M | 156M |
| 17 | securestore | 10M | 166M |
| 18 | sysinfo | 2M | 176M |
| 19 | appinfo | 8M | 178M |
| 20 | backup | 850M | 186M |
| 21 | cache | 850M | 1036M |
| 22 | **system** | **1200M** | **1886M** |
| 23 | shatable | 50M | 3086M |
| 24 | vendor | 200M | 3136M |
| 25 | userdata | rest | 3336M |

XML для инструментов: `firmware/custom/emmc_partitions_q22e.xml`.

Для смены Android достаточно **logo + kernel + system**. Не прошивать `fbl` / `fastboot` / `trustedcore` без бэкапа.

Дамп разделов: `firmware/cyta/extracted/partitions/`.
