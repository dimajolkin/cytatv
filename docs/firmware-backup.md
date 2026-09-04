# Backup / original dump

Каталог: **`build/original/`** (gitignore через `/build/`).

| Путь | Что |
|------|-----|
| `build/original/original.img` | полный eMMC (~7.3G), или |
| `build/original/original.dmg` | сырой дамп с ридера (как «eMMC153 Socket Media.dmg») |
| `build/original/partitions/*.img` | разделы (`q22e init`) |
| `build/original/filesystems/` | system + userdata (`debugfs rdump`) |

```bash
mkdir -p build/original
# dd с Socket или скопируй сырой .dmg с ридера как original.dmg
sudo dd if=/dev/rdiskN of=build/original/original.img bs=4m status=progress

go run ./cmd/q22e init
```

XML слотов: `configs/emmc_partitions_q22e.xml`. Откат на чип — `partitions/` или полный образ.
