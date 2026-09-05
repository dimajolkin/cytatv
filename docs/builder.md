# q22e CLI

```bash
go run ./cmd/q22e wizard
go run ./cmd/q22e ubuntu build
go run ./cmd/q22e ubuntu flash -d diskN --force
go run ./cmd/q22e android-oem-hack build
go run ./cmd/q22e android-oem-hack test   # system.img ↔ yaml (debugfs)
go run ./cmd/q22e android-oem-hack flash -d diskN --force
go run ./cmd/q22e list
go run ./cmd/q22e uart
```

Конфиг: `internal/config` ← `configs/ubuntu.yaml`, `configs/android-oem-hack.yaml`, `configs/uart.yaml` (без ENV).


## android-oem-hack — system_apps

Приложения system uid (сейчас `uid: 1000`). Готовый APK в `assets_dir` — без сборки из cytatv:

```yaml
system_apps:
  - id: settings
    uid: 1000
    apk: Settings.apk
    guest: /priv-app/Settings/Settings.apk
    remove_stock: /app/Settings
```

Settings собирается в sibling **q22e-android-settings** → `Settings.apk` (gitignore),
cytatv подтягивает через assets:

```yaml
  - path: Settings.apk
    url: file://../q22e-android-settings/Settings.apk
```

```bash
cd ../q22e-android-settings && make apk-for-firmware
```

`file://` относительно корня cytatv; при каждом build assets переписывается.

`assets[]` — файлы в `assets_dir` (`url` / `from`+`extract` / опциональный `seed_dir`).

`install_apps[]` — APK из assets → путь в `system.img` (`guest`, опционально `replace`, `optional`).

`launcher` — `preferred_pkg` / `default_launcher` → build.prop / build_hw.prop.

`reserve_apps[]` — пакеты для `/etc/reserveAPP.xml`.

Имена пакетов и список APK — только в yaml; Go их не хардкодит.

После `build`: `go run ./cmd/q22e android-oem-hack test` — guest paths, launcher props, reserve_apps, replace.

`services_patch` — Docker baksmali/smali для `services.jar` (мок compareSignatures).

`su.enabled` — собрать и поставить cytasu (NDK) в образ.

`logo.enabled` — JPEG → HiSi `logo.img` (иначе Cyta splash).

```bash
go run ./cmd/q22e uart              # USB-UART → logs/boot-log-*.txt, Ctrl+C стоп
go run ./cmd/q22e uart /dev/cu.… -b 115200
```

`ubuntu build` / `ubuntu flash` — сборка образа и dd на SD/USB.
