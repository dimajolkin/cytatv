# Linux (Debian e2d) — **legacy**

> **Актуальный путь:** [ubuntu-chroot.md](ubuntu-chroot.md) (Ubuntu Base armhf).  
> e2d после `e2fsck` теряет `/usr/lib` — chroot не стартует.

Скрипты сборки e2d / `prepare-e2d-usb` и локальные образы `firmware/e2d/` удалены.  
Запись носителя: `go run ./cmd/q22e ubuntu flash`.
