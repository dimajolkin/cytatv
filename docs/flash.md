# Прошивка Q22E — актуальный путь

Для этой Cyta: UART read-only на стоке → **только ISP eMMC**.  
Verified boot (ADVCA) не ломаем: родные `bootargs` / `kernel`.

```
build/original/ (бэкап, `q22e init`)
        │
        ▼
  ISP: build/android-oem-hack (logo + kernel + system)
        │
        ▼
  android-oem-hack + Magisk system-root + SSH/ADB
        │
        ├── без носителя: «чистый» Android
        │
        ▼
  SD/USB Ubuntu → cytatv-sd-linux.sh → SSH :22 (root)
```

## 1. Бэкап

Уже есть: [firmware-backup.md](firmware-backup.md) → `build/original/` (`q22e init`).

Перед любой записью: чип в сокете / полный образ сохранён.

## 2. android-oem-hack (из Cyta, без IPTV)

Артефакты в **`build/android-oem-hack/`** (`go run ./cmd/q22e android-oem-hack build`).  
Ассеты: `build/android-oem-hack/assets/`. Settings — `make apk-for-firmware` в `q22e-android-settings` (`Settings.apk` → `file://` в yaml).

| Файл | Слот |
|------|------|
| `logo.img` | 77M / 16M |
| `kernel.img` | 141M / 15M |
| `system.img` | 1886M / 1200M (живой ext4, debloat + root + SD/USB Linux) |

```bash
go run ./cmd/q22e android-oem-hack build
go run ./cmd/q22e android-oem-hack flash -d diskN --force
# sudo запросится в процессе (как ubuntu flash); со сборкой:
# go run ./cmd/q22e android-oem-hack flash -d diskN --force --build --verify
```

Или вручную:

```bash
cd ../eMMC153-Writer && go build -o eMMC153-Worker ./cmd/worker
sudo ./eMMC153-Worker batch \
  --device /dev/rdiskN \
  --android ~/Project/Github/cytatv/build/android-oem-hack \
  --verify
```

`rdiskN` = Socket ~7.8 GB (`diskutil list`). Только **Terminal.app + sudo**.

Откат к стоку: `build/original/partitions/`.  
**Обязательно** wipe **userdata** в batch (старый HOME / Cyta).

## 3. Linux с SD/USB

Образ: `e2d-android-chroot.img` — [linux-install.md](linux-install.md).  
После boot init монтирует e2d, отдаёт **SSH :22 root** и пытается запустить **Enigma2**.

Отключить: `setprop persist.cytatv.sdlinux 0`.

## Чеклист после прошивки

1. SD или USB с e2d вставлена (ehci для USB).
2. Чип в плату → 12V.
3. UART: `go run ./cmd/q22e uart`
   - `cytatv init.bigfish.sh` / hooks
   - при носителе: `sd-linux started` → `sshd ok :22 (root)` → `enigma2 ok|fail`
4. Сеть → SSH: `ssh -i assets/ssh/id_ed25519_q22e root@<IP>` (ключи: `q22e keys`)
5. Без носителя: `su -c id` → `uid=0` (Android)
6. ADB: `adb connect <IP>:5555`
7. Ручной повтор: `/system/xbin/cytatv-sd-linux.sh`

## Что не работает на этой приставке

| Метод | Почему |
|-------|--------|
| HiTool / burn по UART | RX на плате не принимает ввод |
| Recovery «Apply update» | только подписанный Cyta `update.zip` |
| e2d `.upk` / MENU / синяя кнопка | ADVCA; без OEM private key недоступно |
| Правка `bootargs` / hybrid env | RSA → boot loop |
| ADB на стоковой Cyta | debugging вырезан (на custom — tcp 5555) |
