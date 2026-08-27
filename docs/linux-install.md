# Установка Linux (Debian e2d)

**Цель:** Debian 10 + Enigma2 на Hi3798CV200.  
**Сборка:** `firmware/e2d/` ← `./scripts/build-e2d.sh` (источник: `firmware/flash/`).  
**Предусловие:** на eMMC уже **custom Android** — [flash.md](flash.md) / ISP.

На операторской Cyta `.upk` и MENU обычно недоступны.

---

## Файлы

| Путь | Назначение |
|------|------------|
| `firmware/e2d/usb/*.upk` | multiboot MENU |
| `firmware/e2d/usb/*.img` | Linux для USB update |
| `firmware/e2d/sd/*.img` | запись на microSD |

Докачать исходники: `./scripts/download-e2d.sh` → собрать: `./scripts/build-e2d.sh`

---

## 1. Установить `.upk` → MENU

```bash
./scripts/build-e2d.sh
./scripts/prepare-e2d-usb.sh /Volumes/USB menu   # только .upk
# или all — .upk + img (~3.7G)
```

На generic/custom Android: local update / file manager.  
Reboot → на дисплее приставки **MENU**.

| Кнопка пульта | ОС |
|---------------|-----|
| Красная | Android |
| Зелёная | Update (USB → internal) |
| Синяя | **Linux / Enigma2** |

Recovery Cyta **не** ставит `.upk` как OTA — [recovery.md](recovery.md).

---

## 2. Запись Linux на microSD (Mac)

```bash
./scripts/prepare-sdcard.sh firmware/e2d/sd/e2d-armhf-pixel.img
# YES=1 DISK=diskN ./scripts/prepare-sdcard.sh firmware/e2d/sd/e2d-armhf-pixel.img
```

Вставить SD в приставку → MENU → **синяя** кнопка.

---

## 3. Альтернатива: USB update (без SD)

FAT32 USB (`./scripts/prepare-e2d-usb.sh /Volumes/USB all`):

```
e2d-armhf-pixel.img
e2d-armhf-pixel-20210226_K3.18.24.upk
```

MENU → **зелёная** → **UPDT**.

---

## 4. После загрузки

```bash
ssh root@<IP_ПРИСТАВКИ>
```

Kodi вместо Enigma2 (если нужно):

```bash
systemctl disable enigma2
systemctl enable kodi
shutdown -r now
```

---

## Статус

- [x] UART log / inventory
- [x] Backup ISP (`firmware/cyta/`)
- [x] Сборка `firmware/e2d/` (`build-e2d.sh`)
- [ ] ISP → custom Android
- [ ] `.upk` → MENU
- [ ] SD / USB → Linux (синяя кнопка)
