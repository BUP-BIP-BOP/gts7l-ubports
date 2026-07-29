# Bring-up: что было сломано и как чинилось

Хронология сведена к причинам и лечению — чтобы следующий человек не повторял
тупики. Всё ниже проверено на железе, а не выведено из документации.

## Правило, которое стоило суток отладки

**При замене `ubuntu.img` нужно стирать `/data/system-data` и `/data/user-data`.**

Эти каталоги лежат на userdata, а не внутри образа, и переживают его замену. В
них живёт записываемый `/etc` и состояние сессии. Конфигурация от предыдущего
образа поверх нового ломает запуск оболочки так, что симптом выглядит как
проблема графики: композитор рисует спиннер, `lomiri` падает на инициализации
EGL, в логах `must have at least EGL 1.4`.

Сутки ушли на гипотезы про Mir, вложенный режим, права на GPU и версии
платформенных модулей. Все оказались мимо. Помогла очистка данных.

```bash
# в TWRP, перед заливкой нового образа
adb shell 'rm -rf /data/system-data /data/user-data /data/android-data /data/.fscrypt'
```

## Причины, найденные и устранённые

### Загрузчик не отдавал управление ядру

Заставка Samsung висела бесконечно, USB не появлялся.

Виноваты были **не подпись и не board name** — это проверялось и отвергалось:
TWRP грузится без AVB-футера и с чужим product в заголовке. Загрузка пошла,
когда сошлись оффсеты, снятые из стокового boot.img: `ramdisk` 0x02000000 и
`tags` 0x01e00000 — это **не** дефолты mkbootimg, которые используют соседние
порты.

Диагностический признак: заставка висит **без** перезагрузки — загрузчик не
передал управление. Перезагрузка через минуту — ядро работает, падает
пользовательское пространство, сработал сторожевой таймер Qualcomm.

### Контейнер не поднимался без binderfs

`mount-android-partitions` выполняет `mount -t binder binder /dev/binderfs` без
фолбэка. Фрагмент `halium.config` обязан идти **последним** в
`deviceinfo_kernel_defconfig`: он перебивает `halium-extra.config`, где binderfs
выключен ради Waydroid.

### Композитор не стартовал: vndservicemanager

```
E SELinux : Unknown class service_manager
I vndservicemanager: display.qservice : getService has failed, permission denied
E SDM     : HWCSession::Init: Failed to acquire display.qservice
```

Политика SELinux в контейнере не загружается вовсе, класс `service_manager` не
резолвится, и штатный бинарник Samsung отказывает в регистрации по умолчанию.
`androidboot.selinux=permissive` тут не помогает — он лишь отключает
принуждение, а не подставляет политику. Композитор Qualcomm не может
опубликовать `display.qservice` и перезапускается каждые пять секунд.

Лечится подменой `vendor/bin/vndservicemanager` из порта samsung-q2q.

### Overlay не применялся

`deviceinfo_use_overlaystore="true"` уводит весь overlay в `/opt/halium-overlay`,
а механизм наложения умеет только **заменять существующие** файлы. Все новые
файлы порта молча игнорировались:

```
WARNING: //etc/deviceinfo/devices/gts7l.yaml doesn't exist, cannot overlay.
```

Плюс пути, уже содержавшие `opt/halium-overlay`, получали двойную вложенность.
Флаг убран, раскладка описана в [overlay/README.md](../overlay/README.md).

### udev-правила не создавались

Обязательный шаг документации, который легко пропустить: rootfs везёт пустой
`70-android.rules` с комментарием «gets replaced by device-specific rules at
run-time», но никто их не создаёт. Порт генерирует правила при загрузке из
`ueventd.rc` контейнера и вендора — `gts7l-udev-rules.service`.

### Wi-Fi

Драйвер QCA6390 сам не грузится: нужен `modprobe wlan` и запись в `/dev/wlan`
после появления узла. Делает `device-hacks`.

Отдельно маршруты: NetworkManager получает аренду DHCP, но не ставит ни
connected-, ни default-маршрут. Симптом «сеть есть, интернета нет», причём
недоступна и локальная сеть. Ставит диспетчер `50-gts7l-wlan-routes`. Заодно
`swlan0` и `p2p0` выведены из-под управления NetworkManager, иначе он
конкурирует сам с собой.

### Отладочные drop-in'ы, ломающие загрузку

Собственные заплатки с `StandardOutput=append:/var/log/ut-debug/...` роняют юнит,
если каталога нет: `Failed to set up standard output: No such file or directory`.
Каталог создаёт `ut-debug.service`, но он стартует позже оболочки. Если ставишь
такое перенаправление руками — создавай каталог заранее.

## Инструменты отладки

### Дамп с устройства

`ut-debug.service` через минуту после загрузки складывает в `/var/log/ut-debug/`
логи контейнера (`logcat`), `dmesg`, `lshal`, состояние Mir и дисплея, вывод
оболочки и окружение живого процесса `lomiri` из `/proc`.

```bash
./tools/pull-debug.sh          # планшет в TWRP
```

`e2fsck` внутри скрипта обязателен: halium-boot делает `resize2fs` на userdata
при каждой загрузке, и после жёсткого выключения раздел не монтируется с
`I/O error`, пока его не проверишь.

### Лог упавшей загрузки

Переживает перезагрузку:

```bash
adb pull /sys/fs/pstore/console-ramoops-0     # из TWRP
```

`Attempted to kill init!` означает панику из-за завершения init — обычно initrd
не нашёл rootfs.

### Доступ к работающей системе

USB-гаджет под UT пока не поднимается, adb недоступен. Работает SSH по Wi-Fi, но
сервер принимает только ключи:

```bash
# на планшете, в приложении «Терминал»
sudo systemctl disable lxc-android-config-disable-ssh-socket.service
sudo systemctl enable --now ssh
```

Ключ проще доставить по HTTP с рабочей машины: `curl` в образе нет, есть
`python3` и `wget`.

## Открытые вопросы

**Камеры.** Нет пакета `gstreamer1.0-droid` (`droidcamsrc`), и в репозитории
UBports для 24.04-1.x его нет вовсе. Контейнер при этом готов: `libdroidmedia.so`
и `minimediaservice` на месте, узлы `/dev/video0,1,32,33` существуют.

**USB-гаджет.** Под UT устройство не определяется по USB вообще, хотя в TWRP adb
работает. Конфиг usb-moded с VID `04E8` и PID `6860` не помог — нужен разбор
`android_usb`/configfs на этом ядре.

**Bluetooth.** `Failed to connect to bluetooth binder service`.

**Звук и вспышка.** Конфигурация применена по документации, на железе не
проверялась.

## Ссылки

- Ядро с UT-патчами: https://github.com/mukahraman/kernel_samsung_sm8250/tree/ubuntu-touch
- Порт-близнец без модема (SM-T870): https://github.com/iridite/droidian-gts7lwifi
- Рабочий Droidian на SM-T970: https://github.com/mukahraman/galaxy-tab-s7-plus-droidian
- Шаблон Samsung UT-порта: https://gitlab.com/ubports/porting/community-ports/android11/samsung-galaxy-z-fold3/samsung-q2q
- Чеклист UBports: https://docs.ubports.com/en/latest/porting/configure_test_fix/index.html
