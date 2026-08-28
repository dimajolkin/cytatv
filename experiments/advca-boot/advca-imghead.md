# RE: Hisilicon ADVCA ImgHead v2 (Q22E Cyta)

Разбор по дампу `firmware/cyta/extracted/partitions/`.  
Подтверждено на: `bootargs`, `fastboot`, `kernel`, `recovery`, `trustedcore`.

**Итоги ISP-экспериментов** (hybrid env, fbldata, e2d fastboot): [README.md](README.md).

## Layout

```
+0x0000  Magic     "Hisilicon_ADVCA_ImgHead_MagicNum" (32)
+0x0020  Version   "v2.0.0.0" (8)
+0x0028  u32 LE    TotalEnd      — конец образа (после подписи)
+0x002C  u32 LE    DataOffset    — всегда 0x2000
+0x0030  u32 LE    PayloadLen    — = SigOffset - DataOffset
+0x0034  u32 LE    SigOffset     — = TotalEnd - 0x100
+0x0038  u32 LE    HeaderSize    — всегда 0x100
+0x003C..0x00FB    нули
+0x00FC  u32       ? (bootargs: 0xde4c4ebf) + FF padding хвоста заголовка

+0x0100 .. DataOffset-0x100   padding 0xFF
+DataOffset-0x100 .. DataOffset  блок 256 B  («meta», см. ниже)
+DataOffset .. SigOffset         payload
+SigOffset .. TotalEnd           RSA-2048 подпись (ровно 256 B)
```

Инварианты (все проверенные образы):

| | |
|--|--|
| `TotalEnd == SigOffset + 0x100` | ✅ |
| `PayloadLen == SigOffset - DataOffset` | ✅ |
| `DataOffset == 0x2000` | ✅ |
| `HeaderSize == 0x100` | ✅ |

## bootargs специально

| Offset | Содержимое |
|--------|------------|
| `0x1F00..0x2000` | 256 B meta (**бит-в-бит** = `0x12000..0x12100`) |
| `0x2000..0x12000` | U-Boot env, размер блока **0x10000** |
| `0x2000` | CRC32 LE env (`zlib.crc32` по байтам `0x2004..0x11FFF`) |
| `0x2004..` | `key=value\0...\0\0` |
| `0x12000..0x12100` | тот же meta 256 B |
| `0x12100..0x12200` | RSA signature |

`TotalEnd (bootargs) = 0x12200`.

Env CRC на Cyta и e2d: **совпадает** с `zlib.crc32(env[4:0x10000])`.

Meta до/после env одинаковый → это **не** хэш содержимого env.

## Вывод по подписи env

ISP hybrid-smoke (`bootdelay` + CRC, RSA не трогали) → **boot loop**  
→ payload/env **входит в RSA-проверку**. Без private key OEM правки `bootargs` невозможны.

`fbldata` содержит похожую env без ImgHead; cold-boot cmdline маркера оттуда **не** подхватывает (см. boot-experiments).

## Не ADVCA

| Раздел | |
|--------|--|
| `baseparam` | `###` / `BASE_TABLE_*` |
| `fbl` | зашифрован / без magic |
| `system` | меняем свободно |
| `fbldata` | env-копия без ImgHead (не cold-boot source) |

## Инструменты

```bash
cd experiments/advca-boot
./advca-imghead-parse.py ../../firmware/cyta/extracted/partitions/bootargs.img
./build-hybrid-bootargs.sh
./build-fbldata-marker.sh
```
