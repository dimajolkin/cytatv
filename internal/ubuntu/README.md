# internal/ubuntu

Docker context (`Dockerfile`, `scripts/mkimage.sh`) + Go builder:

- `builder.go` — `ubuntu.Build`
- `flash.go` — `ubuntu.Flash`

CLI: `q22e ubuntu build|flash`. Конфиг: `configs/ubuntu.yaml`.
