# Доработка Settings

Проект: **[q22e-android-settings](../../q22e-android-settings/)** → `settings-ui/`.

Править и коммитить только там. cytatv берёт исходники через
`configs/android-oem-hack.yaml` → `system_apps[settings].src_dir: ../q22e-android-settings`.

```bash
# правки в q22e-android-settings, затем:
cd ~/Project/Github/cytatv
go run ./cmd/q22e settings
go run ./cmd/q22e android-oem-hack build
```
