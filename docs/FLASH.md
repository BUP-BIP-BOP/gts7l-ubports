# Прошивка Ubuntu Touch на SM-T875 (gts7l)

> ⚠️ Всё ниже стирает данные и уже подразумевает разлоченный бутлоадер (Knox = 0x1).
> Читай шаг целиком перед выполнением. Ошибка в разделе `super` или `up_param`
> превращает планшет в кирпич, восстанавливаемый только полной стоковой прошивкой.

## 0. Что должно быть на руках

| Файл | Статус |
|---|---|
| `bin/heimdall` | ✅ собран (`tools/build-heimdall.sh`, v1.4.2, arm64) |
| `vbmeta-disabled.img` | ✅ собран (`tools/make-vbmeta.sh`, AVB flags=2, algorithm NONE) |
| `out/boot.img`, `out/dtbo.img`, `out/recovery.img`, `out/ubuntu.img` | ⏳ артефакт CI `gts7l-images` |
| `fw/TWRP-*-gts7lwifi-*.tar` | ✅ скачан — **запасной вариант**, это сборка для Wi-Fi модели |
| `fw/pit.txt` | ✅ снят с устройства, 88 записей |
| Стоковая T875XXS5DXD1 (Android 13, binary 5) | нужна только ради `boot.img` — свериться по оффсетам и `os_patch_level` |

Проверка готовности в любой момент:

```bash
./tools/flash-ut.sh check
```

Recovery берём **свой**, из той же сборки, что и ядро: в `deviceinfo` включён
`deviceinfo_use_unified_recovery` — CI соберёт `recovery.img` с UBports recovery
на нашем ядре и наших dtbo. TWRP от gts7lwifi лежит в `fw/` только на случай,
если своё recovery не поедет: у Wi-Fi модели нет модема, dtb внутри той сборки
чужой.

## 1. База — стоковый Android 13, Halium 13

Halium работает поверх вендор-раздела, который остаётся на устройстве, поэтому
уровень API вендора обязан совпадать с версией Halium.

Счётчик антиотката на этом планшете прожжён в **5**. Проверено практикой:
попытка залить Android 11 (binary 2) отклоняется загрузчиком с

```
FUSED 5 BINARY 2
```

Счётчик необратим, откат невозможен. Расшифровка версий Samsung (проверена на
`T875XXS2BUK2` = binary 2, `B` = Android 11, `U` = 2021, `K` = ноябрь):

```
T875XXS 5 D X D 1
        │ │ │ └── ревизия
        │ │ └──── месяц: A=1 ... L=12
        │ └────── год: U=2021, V=2022, W=2023, X=2024
        └──────── binary (антиоткат) │ после него: B=Android 11, C=12, D=13, E=14
```

binary 5 на этой модели — линейка Android 13, то есть вендор на устройстве уже
API 33. **Стоковую прошивку менять не нужно**, порт переведён на Halium 13
командой `tools/set-halium-version.sh 13` — она синхронно правит `deviceinfo`,
`gbinder.conf` (ApiLevel 33) и версию radio HAL в конфигах ofono.

Стоковый AP нужен только для сверки: `tools/inspect-stock-bootimg.sh` достанет
из него `os_version`, `os_patch_level` и оффсеты boot.img.

## 2. macOS: чем флэшить

Fastboot на этом устройстве **нет** — только Download Mode + протокол Odin.
В brew heimdall отсутствует, поэтому он собран из исходников локально:
`bin/heimdall`, v1.4.2, arm64. Пересобрать — `tools/build-heimdall.sh`.

Апстрим на Apple Silicon не собирается «из коробки», скрипт чинит две вещи:
CMake 4 отвергает `cmake_minimum_required(2.8.4)`, и статический libusb тянет
символы IOKit/CoreFoundation/Security, которые апстрим не линкует.

Стоковую прошивку (4 файла BL/AP/CP/CSC) heimdall'ом лить не надо — только Odin
из Windows-VM. Наши три образа — heimdall'ом.

Если heimdall упрётся в USB (`Protocol initialisation failed!`): другой порт,
кабель из комплекта, USB-2.0 хаб. Запасной путь — Odin/`odin4`.

Download Mode: выключить → **Vol-Down + Vol-Up + подключить USB** → Vol-Up для
подтверждения. Проверка связи:

```bash
./tools/flash-ut.sh pit        # дамп таблицы разделов, ничего не пишет
```

## 3. Разметка (LineageOS BoardConfig, проверено)

| Раздел | Размер, байт |
|---|---|
| BOOT | 71303168 |
| RECOVERY | 86888448 |
| DTBO | 10485760 |
| SUPER | 10171187200 |
| VBMETA | 65536 |

`boot.img` с AVB-футером обязан быть меньше 71303168 байт.

## 4. Recovery

```bash
./tools/flash-ut.sh recovery      # vbmeta + recovery.img, спросит подтверждение
```

Отключить USB, зажать Power+Vol-Down до выключения экрана, **сразу** зажать
Vol-Up + Power — если дать загрузиться стоковому Android, он вернёт своё
recovery на место.

Запасной вариант, если своё recovery не стартует:

```bash
tar -xf fw/TWRP-3.7.1_12-1-gts7lwifi-UNOFFICIAL.tar   # -> recovery.img
IMG_DIR=. ./tools/flash-ut.sh recovery
```

## 5. Rootfs → userdata (вариант A, рекомендуемый)

halium-boot ищет образ как файл `/data/ubuntu.img` на разделе userdata.
Сначала в recovery отформатировать data (в UBports recovery — `Factory reset`
→ `Wipe data`, в TWRP — Wipe → Format Data), затем:

```bash
zstd -d out/ubuntu.img.zst
./tools/flash-ut.sh rootfs        # ~3-4 ГБ, 5-10 минут
```

## 6. Ядро

```bash
./tools/flash-ut.sh kernel        # vbmeta + boot + dtbo одной командой
```

`--VBMETA` включён в **каждую** команду flash скрипта намеренно: одиночные
записи на Samsung SM8250 фиксируются ненадёжно.

Отключить USB → Power → первая загрузка 2–5 минут.

## 7. Вариант B: перепаковка super (продвинутый)

Как в порте Galaxy Z Fold 3: `ubuntu.img` кладётся логическим разделом `system`
внутрь `super` рядом со стоковыми `vendor`/`product`/`odm`, всё пакуется в
TWRP-flashable zip:

```bash
lpmake --metadata-size 65536 --metadata-slots 2 --sparse --super-name super \
  --device super:10171187200 --group ubuntu:$TOTAL \
  --partition system:none:$SYSTEM:ubuntu  --image system=ubuntu.img \
  --partition vendor:none:$VENDOR:ubuntu  --image vendor=vendor.img \
  --partition product:none:$PRODUCT:ubuntu --image product=product.img \
  --partition odm:none:$ODM:ubuntu        --image odm=odm.img \
  --output super.img
```

Плюс: не занимает userdata, штатный OTA-путь UBports. Минус: ошибка = кирпич,
и нужен `lpunpack` стокового `super.img` из прошивки Android 13.

## 7.5 Быстрый откат на сток (без полной прошивки)

Распакуй из AP прошивки Android 13 четыре образа и залей их обратно:

```bash
tools/flash-stock.sh prepare        # SCOPE не важен, распаковывает всё
bin/heimdall flash \
    --VBMETA   fw/unpacked/vbmeta.img \
    --BOOT     fw/unpacked/boot.img \
    --DTBO     fw/unpacked/dtbo.img \
    --RECOVERY fw/unpacked/recovery.img \
    --no-reboot
```

Вернёт загрузку Android, если `super` не трогали. Данные в userdata при этом
остаются в состоянии «занято образом Ubuntu» — понадобится wipe из стокового
recovery.

## 8. Возврат к стоку

Полная прошивка Odin (BL+AP+CP+CSC, HOME_CSC не подойдёт — нужен CSC с wipe),
затем Wipe в стоковом recovery. Knox остаётся сожжённым.

Прошивка обязана быть **binary ≥ 5** — иначе загрузчик ответит `FUSED 5 BINARY x`.

Heimdall для полной прошивки не годится: проверено на этом устройстве —
`PERSIST` записался, а следующий же раздел `MISC` (520 КБ) оборвался на
`Failed to confirm end of file transfer sequence`, и сессия развалилась.
Для стока — Odin из VM или OdinMac. Heimdall оставляем для наших образов.
