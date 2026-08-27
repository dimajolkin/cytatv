# Backup прошивки Cyta

## Статус

**Выполнен** через программатор eMMC153 (ISP).

Каталог: **`firmware/cyta/`**.

## Содержимое

| Путь | Что |
|------|-----|
| `firmware/cyta/eMMC153 Socket Media.dmg` | сырой образ с ридера |
| `firmware/cyta/extracted/emmc_full.img` | полный eMMC (~7.3 GB) |
| `firmware/cyta/extracted/partitions/*.img` | разделы по таблице |
| `firmware/cyta/extracted/filesystems/` | распакованные FS |
| `firmware/cyta/extracted.zip` | архив extracted |

```bash
shasum -a 256 firmware/cyta/extracted/emmc_full.img
shasum -a 256 firmware/cyta/extracted/partitions/*
```

Размеры слотов: [inventory.md](inventory.md). XML: `firmware/custom/emmc_partitions_q22e.xml`.

## ADB

Скрипт `./scripts/adb-backup.sh` — только если на приставке есть ADB. На операторской Cyta debugging вырезан.
