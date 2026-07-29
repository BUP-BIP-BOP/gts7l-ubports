# Bring-up: состояние и порядок отладки gts7l

## Что работает на железе

Проверено логами с устройства, не предположения.

| Слой | Статус | Доказательство |
|---|---|---|
| Ядро 4.19, dtb/dtbo | ✅ | `Hardware name: Samsung GTS7L PROJECT - PV REV0.. (board-id,3)` |
| halium-boot, rootfs | ✅ | initrd монтирует userdata, `boot mode: halium` |
| Android-контейнер | ✅ | `lxc-ls`: RUNNING; `android-set-boot-completion-property` завершился |
| binder, binderfs | ✅ | `/dev/binderfs/{binder,hwbinder,vndbinder}` на месте |
| libhybris | ✅ | `Using hybris leds` |
| GPU | ✅ | `GL renderer: Adreno (TM) 650`, `EGL 1.5 Android META-EGL` |
| Панель, композитор | ✅ | спиннер на экране, `Spinner using native orientation: Landscape` |
| Модем | ✅ | `[gbinder-radio] Connected to android.hardware.radio@1.5::IRadio/slot1` |
| **Оболочка Lomiri** | ❌ | падает на инициализации EGL, см. ниже |

## Текущий блокер

`lomiri` — сервер Mir. Дисплей уже держит системный композитор
(`lomiri-system-compositor`), запущенный от root. Оболочка должна работать
**вложенным** сервером внутри него, но выбирает аппаратную платформу и упирается
в занятый дисплей:

```
mirserver: Starting
Not using logind for session management: TakeControl failed — Only owner of session may take control
Not using Linux VT subsystem: Failed to open current VT
No session management supported
library "eglSubDriverAndroid.so" not found
Exception while creating graphics platform
ERROR: platforms/android/server/gl_context.cpp(64): create_and_initialize_display
std::exception::what: must have at least EGL 1.4
```

### Что уже исключено

| Гипотеза | Проверка | Результат |
|---|---|---|
| Права на GPU-узлы | `lightdm` добавлен в `video`, `system`, `android_graphics`, `render` | не помогло |
| udev-правила | сгенерированы 290 правил из `ueventd.rc` | не помогло само по себе |
| Хост-сокет не задан | `MIR_SERVER_HOST_SOCKET`, `MIR_SOCKET`, аргумент `--host-socket` | платформа всё равно аппаратная |
| Сокет отсутствует | `/run/mir_socket` есть, `srwxrwxrwx` | не причина |
| Модули платформы Mir | подставлены от q2q (ABI .15/.5) | не помогло |
| Wayland-вложение | опции `wayland-host` в Mir 1.8 нет | неприменимо |

### Непроверенная гипотеза

Композитор запускается через `lsc-wrapper`, который выставляет
`LD_PRELOAD=libtls-padding.so` — libhybris требует эту прокладку, потому что
Bionic libc затирает область TLS процесса glibc. Оболочка стартует через
`lomiri-systemd-wrapper`, где этой переменной нет. Единственная оставшаяся
разница между работающим и падающим процессом.

Заплатка добавлена в overlay
(`etc/systemd/user/lomiri-*.service.d/10-gts7l.conf`) и ждёт проверки на железе.

## Инструмент отладки

В образ ставится «чёрный ящик»: `ut-debug.service` через 60 секунд после
загрузки собирает в `/var/log/ut-debug/`:

- `logcat.txt` — лог Android-контейнера, единственное место, где отчитывается HAL композитора
- `dmesg.txt`, `lshal.txt`, `android-ps.txt`, `getprop.txt`
- `mir.txt` — сокеты Mir, права, окружение greeter'а, платформенные модули
- `display.txt` — backlight, `/sys/class/drm`, `/dev/dri`, binderfs
- `greeter.txt`, `lightdm-logs/` — вывод оболочки

Забрать после неудачной загрузки:

```bash
# планшет в TWRP
adb shell 'e2fsck -fy /dev/block/by-name/userdata; mount -t ext4 /dev/block/by-name/userdata /data'
adb pull /data/system-data/var/log/ut-debug logs/
```

`e2fsck` обязателен: halium-boot делает `resize2fs` на userdata, и после жёсткого
выключения раздел не монтируется с `I/O error`, пока его не проверишь.

## Порядок отладки с нуля

### 1. Ядро стартует

Признак провала: заставка висит вечно **без** перезагрузки — загрузчик не передал
управление. Если планшет перезагружается через минуту, ядро работает, а падает
пользовательское пространство: сторожевой таймер Qualcomm.

Лог прошлой загрузки переживает перезагрузку:

```bash
adb pull /sys/fs/pstore/console-ramoops-0     # из TWRP
```

### 2. Контейнер поднимается

```bash
lxc-ls -f                     # ubuntu → RUNNING
journalctl -u mount-android-partitions
getprop | head                # пусто = контейнер мёртв
```

Ловушка, задокументированная в `halium.config` ядра: `mount-android-partitions`
выполняет `mount -t binder binder /dev/binderfs` без фолбэка. Без
`CONFIG_ANDROID_BINDERFS` контейнер не стартует. Фрагмент `halium.config` обязан
идти **последним** в `deviceinfo_kernel_defconfig` — он перебивает
`halium-extra.config`, где binderfs выключен.

### 3. Композитор

`Failed to acquire display.qservice` в logcat означает, что Samsung'овский
`vndservicemanager` отказывает в регистрации сервисов: политика SELinux в
контейнере не загружена, класс `service_manager` не резолвится, и штатный
бинарник по умолчанию отвечает отказом. Лечится подменой из
`overlay/system/opt/halium-overlay/vendor/bin/`.

### 4. Прочее

| Узел | Заметка |
|---|---|
| Wi-Fi | QCA6390, поднимается в `device-hacks` после появления `/dev/wlan` |
| LTE | работает; HAL 1.5, конфиги в `etc/ofono/` |
| S-Pen | Wacom W9021, отдельное устройство ввода, нужны libinput quirks |
| Book Cover | STM32 POGO; ориентацию тачпада правят патчем dtbo |
| USB-C DisplayPort | редрайвер PS5169, в ветке ядра уже включён |
| Камеры | GW3X, последний по очереди пункт |
| Backlight | рабочий узел `panel0-backlight`; пустышку `panel` прячет `device-hacks` |

## Незакрытые пункты чеклиста

**Звук.** Документация требует правок в `/etc/pulse/touch.pa`:

```
- load-module module-droid-discover voice_virtual_stream=true
+ load-module module-droid-discover rate=48000 quirks=+unload_call_exit
```

и в конец файла:

```
### Automatically load the audioflinger glue
.ifexists module-droid-glue-24.so
load-module module-droid-glue-24
.endif
```

Не сделано: overlay заменяет файл целиком, а оригинал из rootfs 24.04 в руки не
дался — в индексе репозитория UBports для noble пакет не нашёлся. Проверять
звук всё равно нечем, пока не запустится оболочка. Когда дойдёт черёд — снять
файл с устройства, поправить и положить в `overlay/system/etc/pulse/touch.pa`.

**Bluetooth.** `bluebinder` в журнале сообщает `Failed to connect to bluetooth
binder service`. Раздел документации про Bluetooth описывает бэкпорт для
Halium 7.1 и к ядру 4.19 неприменим — разбираться по факту, после графики.

**Камеры.** Не трогали.

## Ссылки

- Ядро с UT-патчами: https://github.com/mukahraman/kernel_samsung_sm8250/tree/ubuntu-touch
- Рабочий Droidian-порт T970: https://github.com/mukahraman/galaxy-tab-s7-plus-droidian
- Порт-близнец без модема (T870): https://github.com/iridite/droidian-gts7lwifi
- Шаблон Samsung UT-порта: https://gitlab.com/ubports/porting/community-ports/android11/samsung-galaxy-z-fold3/samsung-q2q
- Чеклист UBports: https://docs.ubports.com/en/latest/porting/configure_test_fix/index.html
