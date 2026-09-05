# Доработка Settings

Проект: **[q22e-android-settings](../../q22e-android-settings/)** → `settings-ui/`.

```bash
cd ~/Project/Github/q22e-android-settings
make apk-for-firmware
# → ./Settings.apk (gitignore)

cd ~/Project/Github/cytatv
go run ./cmd/q22e android-oem-hack build
# assets: url file://../q22e-android-settings/Settings.apk → build/.../assets/Settings.apk
```
