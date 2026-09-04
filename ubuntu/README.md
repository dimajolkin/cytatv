# ubuntu/ — Ubuntu Base chroot image

Docker-сборка rootfs для Cyta (Android kernel + chroot).

```bash
go run ./cmd/q22e ubuntu
# или
./ubuntu/build.sh
```

Выход: `../build/ubuntu/ubuntu-chroot.img`  
Конфиг: `../configs/ubuntu.yaml`  
Доки: [docs/builder.md](../docs/builder.md), [docs/ubuntu-chroot.md](../docs/ubuntu-chroot.md)
