# q22e CLI

```bash
go run ./cmd/q22e wizard
go run ./cmd/q22e ubuntu build
go run ./cmd/q22e ubuntu flash -d diskN --force
go run ./cmd/q22e settings
go run ./cmd/q22e android-oem-hack build
go run ./cmd/q22e android-oem-hack flash -d diskN --force
go run ./cmd/q22e list
go run ./cmd/q22e uart
```

Конфиг: `internal/config` ← `configs/ubuntu.yaml`, `configs/android-oem-hack.yaml`, `configs/uart.yaml` (без ENV).


## android-oem-hack — system_apps

Приложения system uid (сейчас `uid: 1000`), сборка из git:

```yaml
system_apps:
  - id: settings
    uid: 1000
    apk: Settings.apk
    guest: /priv-app/Settings/Settings.apk
    remove_stock: /app/Settings
    repo: git@github.com:dimajolkin/q22e-android-settings.git
    ref: main
    src_dir: build/android-oem-hack/src/q22e-android-settings
    make_target: apk-for-firmware
```

`assets[]` — файлы в `assets_dir` (`url` / `from`+`extract` / опциональный `seed_dir`). Все пути — только из yaml.

`services_patch` — Docker baksmali/smali для `services.jar` (мок compareSignatures).

`su.enabled` — собрать и поставить cytasu (NDK) в образ.

`logo.enabled` — JPEG → HiSi `logo.img` (иначе Cyta splash).

```bash
go run ./cmd/q22e uart              # USB-UART → logs/boot-log-*.txt, Ctrl+C стоп
go run ./cmd/q22e uart /dev/cu.… -b 115200
```

`ubuntu build` / `ubuntu flash` — сборка образа и dd на SD/USB.
