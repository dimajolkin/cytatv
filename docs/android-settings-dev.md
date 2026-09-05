# Доработка Settings

Проект: **[q22e-android-settings](../../q22e-android-settings/)** → `settings-ui/`.

```bash
cd ~/Project/Github/q22e-android-settings
make apk-for-firmware
# → ./Settings.apk (gitignore)

# в cytatv: configs/android-oem-hack.local.yaml
# wifi:
#   ssid: HomeNet
#   psk: "secret"

cd ~/Project/Github/cytatv
go run ./cmd/q22e android-oem-hack build
# assets: file://../q22e-android-settings/Settings.apk
# + /system/etc/wifi/cytatv_default.conf → Settings сидит на BOOT
```
