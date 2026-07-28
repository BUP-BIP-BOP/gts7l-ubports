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
| Стоковая T875XXS2BUK2 (Android 11) | ⏳ качается |

Проверка готовности в любой момент:

```bash
./tools/flash-ut.sh check
```

Recovery берём **свой**, из той же сборки, что и ядро: в `deviceinfo` включён
`deviceinfo_use_unified_recovery` — CI соберёт `recovery.img` с UBports recovery
на нашем ядре и наших dtbo. TWRP от gts7lwifi лежит в `fw/` только на случай,
если своё recovery не поедет: у Wi-Fi модели нет модема, dtb внутри той сборки
чужой.

## 1. Базовая прошивка определяет версию Halium

Halium использует вендор-раздел, который остаётся на устройстве. Уровень API
вендора обязан совпадать с версией Halium.

**Сначала проверь bootloader binary rev** — 5-й символ с конца в номере прошивки
(`T875XXU`**`2`**`BUxx` = BL rev 2):

```bash
adb shell getprop ro.boot.bootloader     # например T875XXU4CWx1 -> rev 4
adb shell getprop ro.build.version.release
```

Samsung не даёт откатиться на прошивку с меньшим BL rev — Odin отвечает
`SW REV CHECK FAIL`. Это необратимо: rev растёт при каждом обновлении.

| Текущий Android | Что делать |
|---|---|
| 11 (One UI 3.x) | ничего, порт уже настроен на Halium 11 |
| 12 | `tools/set-halium-version.sh 12`, либо откат на 11, если BL rev позволяет |
| 13 (One UI 5.x) | `tools/set-halium-version.sh 13` |

Скрипт синхронно правит `deviceinfo`, `gbinder.conf` (ApiLevel) и версию radio
HAL в конфигах ofono.

Стоковую прошивку ставь **целиком** (AP+BL+CP+CSC) через Odin/heimdall, дай
загрузиться, подключи Wi-Fi и подожди ~5 минут — Samsung VaultKeeper должен
«отпустить» бутлоадер, иначе heimdall дойдёт до 100% и завершится с
`session end`, ничего не записав.

> Продвинутый обход анти-роллбэка: с разблокированным бутлоадером и отключённым
> vbmeta можно записать вендор от Android 11 прямо в `super` через TWRP+lpmake,
> не трогая BL — проверки SW REV там нет. Риск: свежий BL/модем против старых
> блобов. Только если Halium 13 не поедет.

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
и нужен `lpunpack` стокового `super.img` из прошивки Android 11.

## 8. Возврат к стоку

Полная прошивка Odin/heimdall (BL+AP+CP+CSC, HOME_CSC не подойдёт — нужен CSC
с wipe), затем Wipe в стоковом recovery. Knox остаётся сожжённым.
