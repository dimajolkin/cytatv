# Linux (Debian e2d) на Cyta — **legacy**

> **Актуальный путь:** [ubuntu-chroot.md](ubuntu-chroot.md) (Ubuntu Base armhf).  
> e2d после `e2fsck` теряет `/usr/lib` — chroot не стартует.

Скрипты сборки e2d/`prepare-e2d-usb` удалены. Образы, если остались локально: `firmware/e2d/`.  
Запись носителя: `go run ./cmd/q22e ubuntu flash`.  
Эксперименты MENU/ADVCA: [experiments/advca-boot/](../experiments/advca-boot/).
