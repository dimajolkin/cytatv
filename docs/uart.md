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
./scripts/uart-capture.sh
# или: screen /dev/cu.usbserial-XXXX 115200
```

В log искать: `mem=`, `blkdevparts=`, `MMC`/`eMMC`.

### Что видно на UART (custom)

| Этап | Содержимое |
|------|------------|
| U-Boot / kernel | как раньше (`console=ttyAMA0,115200`) |
| Android | **logcat** `-b all` → тот же UART |

Уровень: `persist.cytatv.uart.loglevel` (по умолчанию **`V`** — всё).  
Тише: `I` или `D` (через `adb shell setprop …` после сети, либо пересборка).

RX по-прежнему не работает — это только вывод, не shell.

## Известная проблема Q22

После reboot UART может «зависнуть» — переткнуть USB-UART.
