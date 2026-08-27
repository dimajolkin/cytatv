# Hardware — Cyta STB Q22E

## Идентификация

| Поле | Значение |
|------|----------|
| Manufacturer | Huawei |
| Model | **Q22E-E1301** |
| Power | 12V DC, 1.5A |
| SoC | **HiSilicon Hi3798CV200** (`CRBCV200MF3`) |
| Serial | `2153010CLNHYJ8022140 Y Q22E-E1301` |
| PROD ID | `2153010CLNHYJ8523274` |
| MAC (наклейка) | `C4:B8:B4:8F:00:FC` |
| MAC eth (live) | `C4:B8:B4:BF:AB:AB` |
| IP (USB-Ethernet en9) | **`192.168.88.91`** (fixed DHCP) · Mac gateway `192.168.88.1` |
| Firmware | custom (`firmware/custom`), ADB tcp `:5555` |

## Ресурсы (подтверждено)

| | |
|---|---|
| CPU | 4× Cortex-A53, Mali-450, 4K H.265 |
| RAM | **~2 GB** (`mem=1961M`) |
| Flash | **eMMC** ~7.3 GB (полный ISP-дамп) |
| UART | ttyAMA0 **115200**, 3.3V — **только чтение** |

Разделы: [inventory.md](inventory.md).

## Ограничения доступа

| Канал | Статус |
|-------|--------|
| UART | boot log ✅ · shell / U-Boot ❌ |
| ADB | custom: tcp `192.168.88.91:5555` (если adbd поднялся) |
| HiTool burn | нужен TX→SoC ❌ |
| ISP eMMC | **рабочий путь** ✅ · дамп в `firmware/cyta/` |

Прошивка: [flash.md](flash.md). UART: [uart.md](uart.md).

## UART header

Фото: [`photos/03-uart-header.png`](photos/03-uart-header.png)

4 pin у радиатора SoC. Pinout и прозвон: [uart.md](uart.md).

> VCC адаптера **не** подключать при питании 12V.

## eMMC

Чип снимался для ISP-дампа (фото площадки: `photos/13-…`, `14-…`).  
Для нормальной работы платы чип должен быть на месте (или в сокете при ISP-записи).

ISP: [emmc-isp.md](emmc-isp.md).

## Фото

[`photos/README.md`](photos/README.md) — наклейка, SoC, UART, eMMC.

## Справочники SoC

| Ссылка | |
|--------|--|
| [bbs.16rd.com — hi3798cv200](https://bbs.16rd.com/thread-452360-1-1.html) | DataSheet, DC-DC, hardware PDF |
| [Tencent — Hi3798 design](https://cloud.tencent.com/developer/article/2040812) | TFBGA 433, mux, 24 MHz |

Ballmap (DS02 рис. 2-2 / 2-3): [`photos/24-…-part1-A1-AC12.png`](photos/24-hi3798cv200-ballmap-part1-A1-AC12.png), [`photos/25-…-part2-A13-AC23.png`](photos/25-hi3798cv200-ballmap-part2-A13-AC23.png).

Оригинал: **Hi3798C V200 Data Sheet02 — 硬件设计参考**.
