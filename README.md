# Ubuntu Touch — Samsung Galaxy Tab S7 LTE (SM-T875 / `gts7l`)

Порт Ubuntu Touch 24.04 на базе Halium 11. Загружается, работают оболочка
Lomiri, тач, Wi-Fi и модем.

Сборка — GitHub Actions, прошивка — heimdall с macOS или Linux.

## Устройство

| | |
|---|---|
| Модель | SM-T875 (Galaxy Tab S7 LTE), кодовое имя `gts7l` |
| SoC | Qualcomm SM8250 «kona», Snapdragon 865+ |
| Экран | 11", 2560×1600, Novatek NT36523 (тач в панели) |
| GPU | Adreno 650 |
| Звук | 4× Cirrus CS35L41 |
| Wi-Fi/BT | QCA6390 |
| Перо | Wacom W9021 |
| Разметка | A-only, dynamic partitions, **fastboot отсутствует** |
| Ядро | Samsung downstream 4.19 |

## Что работает

| Узел | Статус | Примечание |
|---|---|---|
| Загрузка | ✅ | ядро, halium-boot, Android-контейнер до `boot_completed` |
| Графика | ✅ | Adreno 650, EGL 1.5, композитор и Lomiri |
| Экран блокировки, оболочка | ✅ | |
| Тач | ✅ | |
| Wi-Fi | ✅ | драйвер поднимает `device-hacks` |
| Маршруты и локальная сеть | ✅ | ставит диспетчер NetworkManager |
| Модем | ✅ | `IRadio/slot1`, HAL 1.5, ofono и telepathy стартуют |
| Подсветка | ✅ | путь закреплён в DeviceInfo |
| Звук | ⚠️ | конфиг по документации применён, на железе не проверен |
| Вспышка | ⚠️ | путь прописан, не проверен |
| Камеры | ❌ | нет `gstreamer1.0-droid`, см. «Открытые вопросы» |
| USB-гаджет, adb | ❌ | конфиг usb-moded есть, гаджет не поднимается |
| Bluetooth | ❌ | `bluebinder` не находит сервис |
| Датчики, GPS, камера-вспышка | не проверялись | |

## Быстрый старт

```bash
# 1. Свой форк ядра, свой репозиторий, запуск сборки
gh auth login
./tools/bootstrap-github.sh

# 2. Артефакты последней сборки
RUN=$(gh run list --limit 1 --json databaseId --jq '.[0].databaseId')
gh run download "$RUN" -n gts7l-kernel -D out
gh run download "$RUN" -n gts7l-rootfs -D out
./tools/flash-ut.sh check

# 3. Прошивка — подробности в docs/FLASH.md
./tools/build-heimdall.sh          # heimdall под macOS (форк amo13)
MULTI=1 ./tools/flash-ut.sh recovery
./tools/flash-ut.sh rootfs
MULTI=1 ./tools/flash-ut.sh kernel
```

> **При замене `ubuntu.img` обязательно стирать `system-data` и `user-data`.**
> Конфигурация от предыдущего образа поверх нового ломает загрузку оболочки —
> на этом порту такая смесь стоила суток отладки. Подробности в docs/FLASH.md.

## Структура

```
deviceinfo                     конфигурация для halium-generic-adaptation-build-tools
overlay/system/                файлы, попадающие в rootfs
  etc/                           gbinder, ofono, NetworkManager, pulse, DeviceInfo, udev
  usr/local/bin/                 скрипты порта: udev-правила, маршруты Wi-Fi, сбор логов
  opt/halium-overlay/            подмены внутри Android-контейнера и вендора
.github/workflows/build.yml    две джобы: kernel и rootfs
tools/                         прошивка, подпись образов, диагностика
docs/FLASH.md                  прошивка по шагам
docs/BRINGUP.md                отладка: что было сломано, чем лечится, что открыто
```

## Сборка

Пуш в `master` запускает две джобы:

- **kernel** — ядро, `boot.img`, `dtbo.img`, `recovery.img`, `vbmeta`. Образы подписываются AVB и готовы к записи. ~20 минут, артефакт 67 МБ.
- **rootfs** — `ubuntu.img`. ~10 минут, 700 МБ. Пересобирается только при правках `deviceinfo` или `overlay/`.

Ручной запуск умеет переиспользовать ядро прошлого прогона:

```bash
gh workflow run build.yml -f reuse_kernel_from=<id прогона>
```

Локальная сборка (нужен x86_64 Linux): `./build.sh`

## Открытые вопросы

**Камеры.** В rootfs нет пакета `gstreamer1.0-droid`, дающего `droidcamsrc`, а в
репозитории UBports для ветки 24.04-1.x его нет вовсе — там всего два пакета
gstreamer. Нижний слой при этом на месте: в контейнере есть `libdroidmedia.so`
и `minimediaservice`. Нужно понять, как камеры устроены в этой ветке UT.

**USB-гаджет.** Под Ubuntu Touch планшет не определяется по USB вовсе, хотя в
TWRP adb работает. Конфиг usb-moded с VID/PID Samsung добавлен, но гаджет не
собирается — вероятно, нужен разбор `android_usb`/configfs на этом ядре.
Обходной путь для отладки — SSH по Wi-Fi.

**Bluetooth.** `bluebinder` сообщает `Failed to connect to bluetooth binder
service`.

## На чём основано

- Ядро: [`mukahraman/kernel_samsung_sm8250`](https://github.com/mukahraman/kernel_samsung_sm8250), ветка `ubuntu-touch` — конфиги и device tree для gts7l плюс заметки по bring-up соседнего gts7xl
- Шаблон порта и вендорные бинарники: [`samsung-q2q`](https://gitlab.com/ubports/porting/community-ports/android11/samsung-galaxy-z-fold3/samsung-q2q) (Halium 11, Samsung)
- Починка маршрутов Wi-Fi: [`droidian-gts7lwifi`](https://github.com/iridite/droidian-gts7lwifi) — порт на SM-T870, то же железо без модема
- [Документация UBports по портированию](https://docs.ubports.com/en/latest/porting/index.html)

## Лицензия

Скрипты и конфигурация — [GPL-3.0](LICENSE).

Сторонние файлы в `overlay/`: `vndservicemanager` и `vaultkeeperd` взяты из
порта samsung-q2q, скрипт починки маршрутов адаптирован из droidian-gts7lwifi.
Права принадлежат их авторам.
