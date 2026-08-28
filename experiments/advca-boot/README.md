# Эксперименты: e2d multiboot / ADVCA boot chain (Q22E)

**Дата:** 2026-08-28 … 2026-08-29  
**Цель:** оставить verified boot Cyta и после boot «прыгнуть» в Linux (e2d), в идеале без синей кнопки / с автозапуском.  
**Железо:** Huawei Q22E-E1301, Hi3798CV200, ISP eMMC Socket.  
**Стек на момент тестов:** custom Android (`system`) + родной Cyta `kernel` / `bootargs` (кроме явных STAGE).

Смежная RE-дока по формату образа: [advca-imghead.md](advca-imghead.md).

---

## Исходная гипотеза

1. e2d `.upk` ставит multiboot MENU (синяя = Linux с SD).
2. На Cyta с ADVCA можно либо прошить e2d boot-цепочку через ISP, либо править env, сохранив ADVCA-заголовок.

## Инструменты (эта папка)

| Скрипт | Назначение |
|--------|------------|
| `./build-e2d-boot-experiment.sh` | Достаёт из e2d `.upk` `fastboot` / `bootargs` / `baseparam` / `kernel` (≤15 MiB) → `firmware/e2d/boot-experiment/` |
| `./flash-e2d-boot-experiment.sh` | ISP write по STAGE; `rollback` → сток Cyta boot |
| `./advca-imghead-parse.py` | Парсер ImgHead v2 + env CRC |
| `./build-hybrid-bootargs.sh` | Cyta ADVCA header + same-length правка env + CRC |
| `./build-fbldata-marker.sh` | Маркер `androidboot.fbldata=smoke1` в env `fbldata` |

Запуск из корня репо: `./experiments/advca-boot/<script>.sh`

Образы `*.img` в git **не** коммитятся (`.gitignore`); собираются локально из `firmware/cyta/` + `firmware/flash/`.

Прошивка только из **Terminal.app** + `sudo` (raw `/dev/rdisk*`).

---

## Карта разделов (релевантное)

| Раздел | Offset | ADVCA ImgHead | Роль в тесте |
|--------|--------|---------------|--------------|
| `fbl` | 0 | нет (шифр.) | не трогали |
| `fbldata` | 1 MiB | нет | runtime env / saveenv? |
| `trustedcore` | 2 MiB | да | не трогали |
| `fastboot` | 34 MiB | да (сток) / e2d без | bootmenu e2d |
| `bootargs` | 38 MiB | да | U-Boot env + RSA |
| `baseparam` | 73 MiB | нет | display params |
| `kernel` | 141 MiB | да | слот 15 MiB |
| `system` | 1886 MiB | нет | custom Android |

---

## Результаты по этапам

### STAGE=1 — только e2d `fastboot` @ 34 MiB

| | |
|--|--|
| Команда | `STAGE=1` |
| UART / UI | Android загружается |
| Вывод | SoC **принимает** e2d `fastboot` в этой конфигурации (или уходит в совместимый fallback). MENU e2d сам по себе не проявился. |

### STAGE=2 — e2d `bootargs` + `baseparam` (+ fastboot)

| | |
|--|--|
| `BOOTARGS` | `e2d-linux` (`selectboot=0`) |
| UART | Цикл `Compressed-boot` / `Relocate Boot` **без** `Uncompressing Linux` |
| Вывод | Plain e2d env (другая разметка `blkdevparts`, нет ImgHead) **ломает** загрузку |

Восстановление без полного rollback: обратно Cyta `bootargs` + `baseparam`, e2d `fastboot` оставлен → Android снова OK.

### Hybrid `bootargs` — ADVCA header + правка env

| | |
|--|--|
| Сборка | `./build-hybrid-bootargs.sh` → `bootargs-hybrid-smoke.img` |
| Патч | `bootdelay=0` → `2`, CRC env пересчитан; meta + RSA **не** трогали |
| Flash | `STAGE=bootargs-only BOOTARGS=hybrid-smoke` |
| UART | Boot loop (~34× `Compressed-boot` в `boot-log-20260829-000026.txt` до отката) |
| Вывод | **Env входит в подписанную область.** Без OEM private key правка `bootargs` закрыта. |

Откат: `BOOTARGS=cyta STAGE=bootargs-only` или write стокового `bootargs.img` @ 38 MiB.

### `fbldata` smoke — `bootdelay=0→2`

| | |
|--|--|
| Образ | `fbldata-hybrid-smoke.img` @ 1 MiB |
| Результат | Android грузится (1× Compressed-boot → Linux → cytatv hooks) |
| Вывод | Правка не brick’ает; влияние на boot **не доказано** (delay по UART не виден) |

### `fbldata` marker — допроверка cmdline

| | |
|--|--|
| Сборка | `./build-fbldata-marker.sh` |
| Патч | в env `bootargs` += ` androidboot.fbldata=smoke1` |
| UART cmdline | `androidboot.selinux=disabled console=ttyAMA0…` **без** `androidboot.fbldata=smoke1` |
| Лог | `docs/boot-log-20260829-000844.txt` (локально, в gitignore шаблон `boot-log-*.txt`) |
| Вывод | Cold boot берёт cmdline из подписанного **`bootargs`**, не из `fbldata` |

---

## Сводка

| Гипотеза | Статус |
|----------|--------|
| e2d `.upk` / MENU на Cyta через замену bootargs | ❌ |
| Hybrid: ADVCA header + свой env | ❌ (RSA) |
| `fbldata` как writable boot env | ❌ (игнорируется на cold boot) |
| e2d `fastboot` рядом с Cyta `bootargs`/`kernel` | ✅ Android жив |
| Custom `system` + UART hooks | ✅ |
| Общий публичный ADVCA private key | ❌ (ключи per-operator/OTP; см. ниже) |

### Ключи / «общий сертификат»

По документации HiSilicon (CASignTool, L2/L3): оператор генерирует RSA; public → OTP, private у CA/оператора.  
В `system` лежат `ca_upgrade.pem` (CYTA Root) / OTA — **не** boot ADVCA.  
Тулы для **非高安** Hi3798 к Q22E с SCS не применимы.

---

## Рабочий путь дальше

Verified boot **не ломаем**. Linux:

1. Custom Android (уже) + microSD e2d (образ проверен SHA-256).
2. Из userspace: kexec (если появится в kernel) / chroot / скрипт на SD.
3. Не прошивать unsigned `bootargs` / e2d env на production-чип без отката ISP.

Откат boot-цепочки:

```bash
YES=1 DISK=diskN sudo -E ./flash-e2d-boot-experiment.sh rollback
# или точечно:
# bootargs @ 38MiB, baseparam @ 73MiB, fastboot @ 34MiB, kernel @ 141MiB
# из firmware/cyta/extracted/partitions/
```

---

## Чеклист повтора экспериментов

```bash
cd experiments/advca-boot

# 0) дамп и e2d исходники на месте
./build-e2d-boot-experiment.sh
./build-hybrid-bootargs.sh
./build-fbldata-marker.sh
./advca-imghead-parse.py ../../firmware/cyta/extracted/partitions/bootargs.img

# 1) Socket ~7.8G → diskN (Terminal.app)
YES=1 DISK=diskN STAGE=1 sudo -E ./flash-e2d-boot-experiment.sh
# UART → Android?

YES=1 DISK=diskN STAGE=bootargs-only BOOTARGS=hybrid-smoke \
  sudo -E ./flash-e2d-boot-experiment.sh
# ожидание: loop → сразу rollback bootargs на cyta

YES=1 DISK=diskN sudo -E ../../../eMMC153-Writer/eMMC153-Worker write \
  --device /dev/rdiskN \
  --image ../../firmware/e2d/boot-experiment/fbldata-cmdline-marker.img \
  --offset $((1*1024*1024)) --verify
# UART: grep cmdline — маркера нет
```

(из корня репо: `../eMMC153-Writer/eMMC153-Worker`)

---

## Связанные доки

- [flash.md](../../docs/flash.md) — ISP custom Android  
- [linux-install.md](../../docs/linux-install.md) — e2d MENU/SD (generic путь)  
- [inventory.md](../../docs/inventory.md) — `blkdevparts`  
- [uart.md](../../docs/uart.md) — захват лога  
