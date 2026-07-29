# Ubuntu Touch → Samsung Galaxy Tab S7 LTE (SM-T875 / `gts7l`)

Порт Ubuntu Touch 24.04 на базе Halium 13 для SM-T875. Сборка — GitHub Actions,
прошивка — heimdall с macOS.

## Железо

| | |
|---|---|
| Модель | SM-T875 (Galaxy Tab S7 LTE), кодовое имя `gts7l` |
| SoC | Qualcomm SM8250 «kona», Snapdragon 865+ |
| Экран | 11" 2560×1600 LCD, панель Novatek NT36523 (TDDI, тач в панели) |
| Звук | 4× Cirrus CS35L41 |
| Wi-Fi/BT | QCA6390 |
| Перо | Wacom W9021 |
| Разметка | A-only, dynamic partitions (`super`), **fastboot нет** |
| Ядро | Samsung downstream 4.19 |

## На чём стоит порт

Полного AOSP-дерева собирать не нужно: с Halium 9+ UBports использует
«standalone kernel» — собирается только ядро, rootfs и Android-контейнер
скачиваются готовыми.

- **Ядро**: [`mukahraman/kernel_samsung_sm8250`](https://github.com/mukahraman/kernel_samsung_sm8250),
  ветка `ubuntu-touch` — уже содержит `vendor/samsung/gts7l.config`, все
  `kona-sec-gts7l-*-overlay-r0*.dts`, `halium.config` с UT-фиксами и живые
  заметки по отладке от bring-up соседнего gts7xl (июнь 2026).
- **Соседи**: Droidian на SM-T970 (`gts7xlwifi`) работает полностью; порт на
  SM-T870 (`gts7lwifi`) готов и ждёт железа. T875 = T870 + модем.
- **Шаблон UT-порта**: Samsung Galaxy Z Fold 3 (`samsung-q2q`, Halium 11,
  UT 24.04) — оттуда взяты overlay-конфиги (gbinder, ofono, sensorfw).

## Статус

- [x] deviceinfo: разметка из LineageOS BoardConfig, оффсеты сняты со стокового boot.img
- [x] CI: две джобы — ядро (быстро, подписанные образы) и rootfs
- [x] heimdall под macOS, PIT снят, прошивка отработана
- [x] **Загружается**: ядро, halium-boot, Android-контейнер до `boot_completed`
- [x] **GPU и панель**: Adreno 650, EGL 1.5, композитор рисует
- [x] **Модем**: `IRadio/slot1` по HAL 1.5, ofono и telepathy подняты
- [x] Чеклист UBports: udev-правила, AppArmor как LSM, overlay по документации
- [ ] **Оболочка Lomiri** — падает на EGL, см. [docs/BRINGUP.md](docs/BRINGUP.md)
- [ ] Тач / звук / камеры / Wi-Fi

## Порядок работ

```bash
# 1. GitHub: форк ядра + создание репо + запуск сборки (нужен gh auth login)
./tools/bootstrap-github.sh

# 2. Планшет подключён по USB с включённой отладкой:
./tools/collect-device-info.sh      # -> device-facts.txt

# 3. Когда скачана стоковая прошивка Android 13 (binary >= 5):
./tools/inspect-stock-bootimg.sh AP_T875XXS5DXD1*.tar.md5   # -> os_version/patch_level

# 4. Прошивка
./tools/build-heimdall.sh           # -> bin/heimdall (форк amo13)
./tools/make-vbmeta.sh              # -> vbmeta-disabled.img
./tools/sign-images.sh              # AVB-футер + board name, иначе ABL не грузит
./tools/flash-ut.sh check

# 5. Дамп с неудачной загрузки (планшет в TWRP)
./tools/pull-debug.sh
```

## Сборка

Пушнуть в GitHub → workflow `build` соберёт `boot.img`, `dtbo.img`,
`ubuntu.img.zst` и положит в артефакт `gts7l-images` (~40 минут).

Локально (нужен x86_64 Linux; на Apple Silicon — `docker run --platform linux/amd64`):

```bash
./build.sh
```

## Прошивка

См. [docs/FLASH.md](docs/FLASH.md). Кратко: стоковый Android 13 остаётся на
месте как база вендор-блобов (API 33) → своё UBports recovery → `ubuntu.img`
в `/data/ubuntu.img` → heimdall `--VBMETA --BOOT --DTBO`.

## Отладка

См. [docs/BRINGUP.md](docs/BRINGUP.md) — порядок bring-up и известные ловушки
семейства (binderfs, vaultkeeperd, HCI-socket, PS5169).

## Текущий блокер

Всё ниже оболочки работает. `lomiri` должен запускаться вложенным сервером Mir
внутри системного композитора, но выбирает аппаратную платформу и падает на
`must have at least EGL 1.4`, потому что дисплей уже занят. Разбор гипотез и
что уже исключено — в [docs/BRINGUP.md](docs/BRINGUP.md).

## Что нужно проверить на живом устройстве

Помечено `VERIFY` в [deviceinfo](deviceinfo) и overlay-файлах:

1. ~~Оффсеты boot.img~~ — сняты со стокового образа: ramdisk `0x02000000`,
   tags `0x01e00000` (не дефолты mkbootimg!). Сверить, что в Android 13 те же
2. `os_version` / `os_patch_level` — сейчас значения от Android 11, заменить
   на снятые из T875XXS5DXD1
3. Ревизия платы (`ro.boot.hw_rev`) → какой `overlay-rNN.dtbo` выбирает бутлоадер
4. Регион: CSC `SER`, dtbo сейчас EUR; сверить с `hw_rev`
5. Версия radio HAL (сейчас 1.6) → `lshal | grep radio` внутри контейнера
6. Пути backlight/flashlight в `gts7l.yaml`
7. Список модулей → `tools/gen-modules-load.sh`
