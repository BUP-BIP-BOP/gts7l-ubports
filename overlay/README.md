# Overlay

Файлы отсюда попадают в rootfs при сборке. Раскладка подчиняется правилам
UBports для портов **без** `deviceinfo_use_overlaystore`:

- `overlay/system/<путь>` → `/<путь>` в образе, файл записывается напрямую.
  Только так можно добавить в систему **новые** файлы.
- `overlay/system/opt/halium-overlay/<путь>` → `/opt/halium-overlay/<путь>`,
  откуда механизм наложения при загрузке монтирует файл поверх `/<путь>`.
  Работает только для **замены существующих** файлов — в том числе внутри
  Android-контейнера и вендорного раздела.

Попытка добавить новый файл через `/opt/halium-overlay` тихо ничего не делает и
пишет в журнал `... doesn't exist, cannot overlay`.

## Что где лежит

| Путь | Назначение |
|---|---|
| `etc/deviceinfo/devices/gts7l.yaml` | параметры устройства для libdeviceinfo: тип, GridUnit, ориентация, пути подсветки и вспышки |
| `etc/ubuntu-touch-session.d/android.conf` | те же параметры в устаревшем формате — документация требует держать оба |
| `etc/gbinder.conf` | уровень API вендора (30) для gbinder |
| `etc/ofono/` | модем: плагин binder, radio HAL 1.5, один слот |
| `etc/NetworkManager/` | Wi-Fi: `swlan0` и `p2p0` вне управления, диспетчер маршрутов |
| `etc/pulse/touch.pa` | звук по инструкции UBports |
| `etc/sensorfw/` | датчики через HIDL |
| `etc/default/lsc-wrapper.d/` | флаги системного композитора: HWC2, композиция на GPU |
| `etc/default/usb-moded.d/` | VID/PID Samsung для USB |
| `etc/systemd/` | сервисы порта и drop-in'ы для юнитов оболочки |
| `usr/local/bin/` | скрипты: генерация udev-правил, починка маршрутов, сбор диагностики |
| `opt/halium-overlay/vendor/bin/` | замены вендорных бинарников |
| `opt/halium-overlay/usr/libexec/lxc-android-config/device-hacks` | инициализация Wi-Fi и модема после старта контейнера |
