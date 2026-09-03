# scripts (macOS)

| Скрипт | |
|--------|--|
| `build-custom-android.sh` | custom `system.img` (Lawnchair, cytasu root, SD Linux autostart) |
| `build-wifihub.sh` | APK «Wi‑Fi» → `assets/extras/WifiHub.apk` |
| `flash-custom-emmc.sh` | ISP Socket → Worker batch (нужен sudo / Terminal) |
| `build-e2d.sh` | пакет `firmware/e2d/` |
| `download-e2d.sh` | скачать исходники e2d в `firmware/flash/` |
| `prepare-sdcard.sh` | dd e2d-android-chroot на SD/USB |
| `repack-e2d-for-android.sh` | e2d → ext4 без 64bit (chroot с Android) |
| `prepare-e2d-usb.sh` | `.upk` на FAT USB (MENU) |
| ADVCA/e2d boot-эксперименты | → [experiments/advca-boot/](../experiments/advca-boot/) |
| `uart-capture.sh` | лог UART |
| `stb-en9-dhcp.sh` | DHCP на USB-Ethernet en9 |
| `find-stb.sh` | поиск ADB в LAN |
| `parse-boot-log.sh` / `parse-partitions.sh` | разбор логов |
| `emmc-isp-annotate/` | разметка фото ISP |
| `hisi-logo/` | нейтральный splash |
