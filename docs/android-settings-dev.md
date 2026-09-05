# Доработка Settings

Проект: **[q22e-android-settings](../../q22e-android-settings/)** → `settings-ui/`.

Сборка APK только там. cytatv берёт готовый `build/android-oem-hack/assets/Settings.apk`.

```bash
cd ~/Project/Github/q22e-android-settings
make apk-for-firmware
# → ../cytatv/build/android-oem-hack/assets/Settings.apk

cd ~/Project/Github/cytatv
go run ./cmd/q22e android-oem-hack build
```
