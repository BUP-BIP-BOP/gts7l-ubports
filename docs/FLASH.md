# Прошивка Ubuntu Touch на SM-T875 (gts7l)

> ⚠️ Всё ниже стирает данные и уже подразумевает разлоченный бутлоадер (Knox = 0x1).
> Читай шаг целиком перед выполнением. Ошибка в разделе `super` или `up_param`
> превращает планшет в кирпич, восстанавливаемый только полной стоковой прошивкой.

## 0. Что должно быть на руках

| Файл | Откуда |
|---|---|
| `boot.img`, `dtbo.img`, `ubuntu.img` | артефакт CI (`gts7l-images`) |
| `vbmeta-disabled.img` | `tools/make-vbmeta.sh` |
| TWRP для gts7l | собрать из [ianmacd/twrp_gts7l](https://github.com/ianmacd/twrp_gts7l) или взять сборку для gts7lwifi/gts7l с XDA |
| Стоковая прошивка Android 11 (One UI 3.1), `T875XXU*` | samfw.com / Frija — нужна для вендор-блобов API 30 |

## 1. Базовая прошивка = Android 11

Halium 11 ждёт вендор-раздел уровня API 30. Ставь стоковый One UI 3.1 **целиком**
через Odin/heimdall (AP+BL+CP+CSC), дай загрузиться, подключи Wi-Fi и подожди
~5 минут — Samsung VaultKeeper должен «отпустить» бутлоадер, иначе heimdall
дойдёт до 100% и завершится с `session end` ничего не записав.

Даунгрейд с Android 12/13 на 11 блокируется анти-роллбэком (`up_param`/bootloader
rev). Если стоковый Android 11 не принимается — оставайся на текущей версии и
переключи порт на соответствующий Halium (13 для Android 13) в `deviceinfo`.

## 2. macOS: чем флэшить

Fastboot на этом устройстве **нет** — только Download Mode + протокол Odin.
`brew install heimdall` не существует, собираем из исходников:

```bash
brew install libusb cmake qt@5
git clone https://github.com/Benjamin-Dobell/Heimdall
cd Heimdall && mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release && make -j"$(sysctl -n hw.ncpu)"
sudo make install
heimdall version
```

Если heimdall на macOS упирается в USB (`Protocol initialisation failed!`) —
запасной путь: Odin на Windows/VM или `odin4` (Linux x86_64) в UTM.

Download Mode: выключить → **Vol-Down + Vol-Up + подключить USB** → Vol-Up для
подтверждения.

## 3. Разметка (LineageOS BoardConfig, проверено)

| Раздел | Размер, байт |
|---|---|
| BOOT | 71303168 |
| RECOVERY | 86888448 |
| DTBO | 10485760 |
| SUPER | 10171187200 |
| VBMETA | 65536 |

`boot.img` с AVB-футером обязан быть меньше 71303168 байт.

## 4. Установка TWRP

```bash
heimdall flash --VBMETA vbmeta-disabled.img --RECOVERY twrp-gts7l.img --no-reboot
```

Отключить USB, зажать Power+Vol-Down до выключения, затем сразу
**Vol-Up + Power** — иначе стоковый Android перезапишет recovery.

## 5. Rootfs → userdata (вариант A, рекомендуемый)

halium-boot ищет образ как файл `/data/ubuntu.img` на разделе userdata.

В TWRP: Wipe → Format Data (ext4), затем с Mac:

```bash
zstd -d ubuntu.img.zst
adb shell mkdir -p /data
adb push ubuntu.img /data/ubuntu.img     # ~3-4 ГБ, 5-10 минут
adb shell sync
```

## 6. Ядро

```bash
heimdall flash \
    --VBMETA vbmeta-disabled.img \
    --BOOT boot.img \
    --DTBO dtbo.img \
    --no-reboot
```

`--VBMETA` включать в **каждую** команду flash: одиночные записи на Samsung
SM8250 фиксируются ненадёжно.

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
