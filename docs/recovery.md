# Recovery — «Update not found»

## Почему так

**Apply update from external storage** ищет **подписанный OTA** Cyta/Huawei (`update.zip`), а не:

| На флешке | Recovery примет? |
|-----------|------------------|
| `.upk` (e2d) | ❌ |
| `logo.img` / `kernel.img` / `system.img` | ❌ |
| Ubuntu Live USB | ❌ |
| Официальный Cyta `update.zip` | ✅ (остаётесь на Cyta) |

## Что делать

Прошивка этой приставки — **ISP eMMC**: [flash.md](flash.md).

После generic Android `.upk` ставят из Android UI / другого updater, не из Cyta recovery OTA.

## USB-порт

Рабочий: **ehci** → `sda/sda1` в UART-логе.  
Не использовать порт с `usb 5-1 error -71`.
