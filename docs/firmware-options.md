# Варианты прошивки

Актуально: **[flash.md](flash.md)** (macOS + ISP).

| Цель | Как |
|------|-----|
| Откат Cyta | `firmware/cyta/` |
| Custom Android + root | `./scripts/build-custom-android.sh` → eMMC153-Worker batch |
| Linux e2d | microSD + автозапуск chroot — [linux-install.md](linux-install.md) |

На этой Cyta **не** использовать: HiTool burn, recovery OTA под `.upk`, MENU / синяя кнопка.
