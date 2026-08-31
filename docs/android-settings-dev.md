# Доработка Settings

Проект: **[q22e-android](../../q22e-android/)** → `settings-ui/`.

Путь: расширять стоковый Settings (smali/apktool), не подменять урезанным UI.
Временный Kotlin UI в `settings-ui` — прототип экранов ADB/SSH.

```bash
cd ~/Project/Github/q22e-android/settings-ui && make apk-for-firmware
cd ~/Project/Github/cytatv && ./scripts/build-custom-android.sh
```
