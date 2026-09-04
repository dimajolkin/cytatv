# UART — Huawei Q22E (Hi3798CV200)

## Параметры

| Параметр | Значение |
|----------|----------|
| Напряжение | **3.3V** (не 5V) |
| Baud | **115200** 8N1 |
| На этой Cyta | **только чтение** (boot log) |

## Статус (эта приставка)

Boot log есть. Ввод в U-Boot/shell **не принимается**.

| Работает | Не работает |
|----------|-------------|
| Захват log | Интерактивный shell |
| `blkdevparts`, RAM из cmdline | HiTool burn (нужен TX ПК → плата) |

Прошивка: [flash.md](flash.md) (ISP). Железо: [hardware.md](hardware.md).

## Подключение

```
USB-UART          Плата STB
────────          ────────
  RX      ←──→     TX
  TX      ←──→     RX   (на Cyta команды всё равно игнорируются)
  GND     ───      GND
  VCC     ✗        не подключать
```

Header: 4 pin у радиатора SoC — [hardware.md](hardware.md), фото `photos/03-uart-header.png`.

### Прозвон

1. **GND** (выкл.): continuity → корпус / радиатор  
2. **VCC** (вкл. 12V): стабильно 3.3V — к адаптеру не цеплять  
3. **TX**: скачет при boot → на RX адаптера  
4. **RX**: ~3.3V стабильно → на TX адаптера  

Pad 3–4 (с трасами) — почти наверняка TX/RX.

## Захват лога (macOS)

```bash
go run ./cmd/q22e uart
# или: go run ./cmd/q22e uart /dev/cu.usbserial-XXXX
# Ctrl+C — стоп и сохранить docs/boot-log-*.txt
```

В log искать: `mem=`, `blkdevparts=`, `MMC`/`eMMC`.

### Что видно на UART (custom)

| Этап | Содержимое |
|------|------------|
| Bootloader | `Compressed-boot`, `Uncompressing Linux...` |
| Kernel / init | `/proc/kmsg` → ttyAMA0 (после `init.bigfish.sh`) |
| Android | **logcat** `-b all` → тот же UART |

На **normal boot** loader часто обрывается на `booting the kernel` — это нормально для Q22E; дальше лог идёт только когда Android доходит до `init.bigfish.sh` (обычно +30–60 с).

Хук: `init.bigfish.sh` + `logd.rc` (Android 7 не всегда читает `custom_uart.rc`).

Уровень: `persist.cytatv.uart.loglevel` (по умолчанию **`V`** — всё).  
Тише: `I` или `D` (через `adb shell setprop …` после сети, либо пересборка).

RX по-прежнему может не работать на железе Q22E. В прошивке включён эксперимент **`uart-shell.sh`**: читает команды с `/dev/ttyAMA0`, выполняет через `sh -c`, ответ → UART.

```
help          — список
id            — whoami
getprop ro.build.display.id
reboot
exit          — выйти из shell-цикла
```

Отключить: `setprop persist.cytatv.uart.shell 0` (после ADB) или пересборка с `0` в build.prop.

В **picocom** можно печатать команды — если RX жив, увидишь `#` prompt и вывод.

## Известная проблема Q22

После reboot UART может «зависнуть» — переткнуть USB-UART.
