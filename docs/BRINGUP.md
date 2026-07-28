# Bring-up: порядок отладки gts7l

Порядок жёсткий — каждый следующий пункт бессмысленно чинить, пока не работает
предыдущий.

## 1. Ядро вообще стартует

Симптом провала: чёрный экран, ребут-луп, вибрация.

- Собрать boot.img с `deviceinfo_kernel_cmdline` + `androidboot.debug`, загрузиться,
  подключить USB. halium-boot поднимает RNDIS и telnet-rescue при провале initrd.
- На Mac интерфейс появится как `enX`: `sudo ifconfig enX 192.168.2.1/24`,
  затем `telnet 192.168.2.15`.
- Смотреть `dmesg`, `/proc/last_kmsg`, `cat /proc/cmdline`.
- Типичные причины: не тот `dtbo` (ревизия платы), header v2 не совпал,
  boot.img больше 71303168 байт, забыт `--VBMETA` при флэше.

Ревизия платы: `adb shell getprop ro.boot.hw_rev` на стоке → выбрать
`kona-sec-gts7l-eur-overlay-rNN.dtbo`.

## 2. Android-контейнер поднимается

Симптом: загрузка идёт, но нет графики.

```bash
sudo lxc-ls -f                       # ubuntu должен быть RUNNING
sudo systemctl status lxc-android-config
journalctl -u mount-android-partitions
getprop | head                       # пусто => контейнер мёртв
```

Известная ловушка этого семейства (задокументирована в `halium.config` ядра):
`mount-android-partitions` делает `mount -t binder binder /dev/binderfs` без
фолбэка. Если `CONFIG_ANDROID_BINDERFS` выключен — контейнер не стартует,
`lightdm` циклится 5 раз, чёрный экран. Фрагмент `halium.config` должен идти
**последним** в `deviceinfo_kernel_defconfig`.

Второе: Samsung `vaultkeeperd` в вендоре может блокировать запуск сервисов —
в порте Z Fold 3 его подменяют заглушкой в
`overlay/system/opt/halium-overlay/vendor/bin/vaultkeeperd`.

## 3. Графика

```bash
test_hwcomposer                      # должен рисовать градиент
cat /sys/class/drm/card0-DSI-1/status
journalctl -u lightdm
```

`Mir android2 priority 0 "Failed to find platform"` = HAL из контейнера не
поднялся, возвращайся к шагу 2.

## 4. Тач

Novatek NT36523 (TDDI, встроен в панель).

```bash
cat /proc/bus/input/devices | grep -A5 touch    # ждём sec_touchscreen
evtest
```

## 5. Звук

4 усилителя Cirrus CS35L41. Ядро поднимает ASoC-карту, но ACDB-калибровка
загружается только внутри Android audio HAL — pulseaudio должен идти через
`droid card`, не через ALSA напрямую.

```bash
pactl list sinks | grep -i droid
```

## 6. LTE / модем

Разница с gts7lwifi: у T875 есть модем, значит нужен ofono + binder-плагин
(`overlay/system/etc/ofono/`).

```bash
/usr/sbin/ofonod -d -n                # смотреть, находит ли slot1
lshal | grep radio                    # версия HAL: 1.4 или 1.5 -> в qti.conf
```

## 7. Прочее

| Узел | Заметка |
|---|---|
| Wi-Fi/BT | QCA6390, модули `cnss2`; LineageOS вырезал HCI-socket в ядре — в T970-порте это чинили патчем `net/bluetooth/hci_sock.c` |
| S-Pen | Wacom W9021, отдельное устройство ввода, нужны libinput quirks |
| Book Cover клавиатура | STM32 POGO; ориентацию тачпада правят патчем dtbo (`touchpad,invert`) |
| USB-C DisplayPort | редрайвер PS5169 — в ветке `ubuntu-touch` уже включён |
| Камеры | GW3X; ожидаемо последний по очереди пункт |

## Полезные ссылки

- Рабочий Droidian-порт T970: https://github.com/mukahraman/galaxy-tab-s7-plus-droidian
- Порт T870 (наш близнец без модема): https://github.com/iridite/droidian-gts7lwifi
- Ядро с UT-патчами: https://github.com/mukahraman/kernel_samsung_sm8250/tree/ubuntu-touch
- Шаблон Samsung UT-порта: https://gitlab.com/ubports/porting/community-ports/android11/samsung-galaxy-z-fold3/samsung-q2q
- Документация UBports: https://docs.ubports.com/en/latest/porting/build_and_boot/standalone_kernel_build.html
