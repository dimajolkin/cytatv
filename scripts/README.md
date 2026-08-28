# scripts (macOS)

| Скрипт | |
|--------|--|
| `build-custom-android.sh` | custom `system.img` (Lawnchair, root, apps) |
| `build-wifihub.sh` | APK «Wi‑Fi» → `assets/extras/WifiHub.apk` |
| `flash-custom-emmc.sh` | ISP Socket → Worker batch (нужен sudo / Terminal) |
| `build-e2d.sh` | пакет `firmware/e2d/` |
| `download-e2d.sh` | скачать исходники e2d в `firmware/flash/` |
| `prepare-sdcard.sh` | dd e2d на microSD |
| `prepare-e2d-usb.sh` | `.upk` на FAT USB (MENU) |
| `build-e2d-boot-experiment.sh` | e2d fastboot/bootargs/kernel для ISP-тестов |
| `flash-e2d-boot-experiment.sh` | STAGE/rollback boot-цепочки на Socket |
| `build-hybrid-bootargs.sh` | Cyta ADVCA + правка env (smoke) |
| `build-fbldata-marker.sh` | маркер cmdline в `fbldata` |
| `advca-imghead-parse.py` | парсер ImgHead v2 |
| `uart-capture.sh` | лог UART |
| `stb-en9-dhcp.sh` | DHCP на USB-Ethernet en9 |
| `find-stb.sh` | поиск ADB в LAN |
| `parse-boot-log.sh` / `parse-partitions.sh` | разбор логов |
| `emmc-isp-annotate/` | разметка фото ISP |
| `hisi-logo/` | нейтральный splash |
