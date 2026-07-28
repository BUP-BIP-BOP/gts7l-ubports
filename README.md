# Ubuntu Touch → Samsung Galaxy Tab S7 LTE (SM-T875 / `gts7l`)

Порт Ubuntu Touch 24.04 на базе Halium 11 для SM-T875. Сборка — GitHub Actions,
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

- [x] deviceinfo собран из проверенных значений (LineageOS BoardConfig + Droidian kernel-info)
- [x] CI на GitHub Actions (ubuntu:22.04 контейнер — нужны libtinfo5 и python2)
- [x] Overlay-заготовки: gbinder API 30, ofono binder (LTE), sensorfw HIDL, deviceinfo.yaml
- [ ] Первая сборка ядра
- [ ] Первая загрузка
- [ ] Тач / графика / звук / LTE

## Порядок работ

```bash
# 1. GitHub: форк ядра + создание репо + запуск сборки (нужен gh auth login)
./tools/bootstrap-github.sh

# 2. Планшет подключён по USB с включённой отладкой:
./tools/collect-device-info.sh      # -> device-facts.txt
./tools/set-halium-version.sh 13    # только если сток НЕ Android 11

# 3. Когда скачана стоковая прошивка:
./tools/inspect-stock-bootimg.sh AP_T875*.tar.md5   # -> os_version/patch_level
./tools/make-vbmeta.sh                              # -> vbmeta-disabled.img
```

## Сборка

Пушнуть в GitHub → workflow `build` соберёт `boot.img`, `dtbo.img`,
`ubuntu.img.zst` и положит в артефакт `gts7l-images` (~40 минут).

Локально (нужен x86_64 Linux; на Apple Silicon — `docker run --platform linux/amd64`):

```bash
./build.sh
```

## Прошивка

См. [docs/FLASH.md](docs/FLASH.md). Кратко: стоковый Android 11 (One UI 3.1) как
база вендор-блобов → TWRP → `ubuntu.img` в `/data/ubuntu.img` → heimdall
`--VBMETA --BOOT --DTBO`.

## Отладка

См. [docs/BRINGUP.md](docs/BRINGUP.md) — порядок bring-up и известные ловушки
семейства (binderfs, vaultkeeperd, HCI-socket, PS5169).

## Что нужно проверить на живом устройстве

Помечено `VERIFY` в [deviceinfo](deviceinfo) и overlay-файлах:

1. `os_version` / `os_patch_level` из стокового `boot.img`
2. Ревизия платы (`ro.boot.hw_rev`) → какой `overlay-rNN.dtbo` выбирает бутлоадер
3. Регион: EUR / KOR / USA — набор dtbo в `deviceinfo_dtbo`
4. Версия radio HAL (1.4 vs 1.5) → `overlay/system/etc/ofono/*`
5. Пути backlight/flashlight в `gts7l.yaml`
6. Список модулей → `tools/gen-modules-load.sh`
