# Прошивка Q22E — актуальный путь

Для этой Cyta: UART read-only, ADB в UI нет → **только ISP eMMC**.

```
firmware/cyta/ (бэкап ✅)
        │
        ▼
  ISP: firmware/custom (logo + kernel + system)
        │
        ▼
  Generic Android (без Cyta IPTV)
        │
        ├── стоп: «чистый» Android
        │
        ▼
  firmware/flash/*.upk → MENU → SD e2d → синяя кнопка = Linux
```

## 1. Бэкап

Уже есть: [firmware-backup.md](firmware-backup.md) → каталог `firmware/cyta/`.

Перед любой записью: чип в сокете / полный образ сохранён.

## 2. Custom Android (из Cyta, без IPTV)

Файлы в **`firmware/custom/`** (сборка: `./scripts/build-custom-android.sh`):

| Файл | Слот |
|------|------|
| `logo.img` | 77M / 16M |
| `kernel.img` | 141M / 15M |
| `system.img` | 1886M / 1200M (живой ext4, debloat + ADB) |

```bash
./scripts/build-custom-android.sh

cd ../eMMC153-Writer && go build -o eMMC153-Worker ./cmd/worker
sudo ./eMMC153-Worker batch \
  --device /dev/rdiskN \
  --android ~/Project/Github/cytatv/firmware/custom \
  --verify
```

`rdiskN` = Socket ~7.8 GB (`diskutil list`). Только **Terminal.app + sudo**.

Откат к стоку: `firmware/cyta/`.

## 3. Linux (опционально)

Сборка: **`firmware/e2d/`** ← `./scripts/build-e2d.sh` (исходники в `firmware/flash/`).  
После custom Android: [linux-install.md](linux-install.md).

## Что не работает на этой приставке

| Метод | Почему |
|-------|--------|
| HiTool / burn по UART | RX на плате не принимает ввод |
| Recovery «Apply update» | только подписанный Cyta `update.zip` |
| ADB на стоковой Cyta | debugging вырезан (на custom — tcp 5555) |
