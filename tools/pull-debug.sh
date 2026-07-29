#!/bin/bash
# Pull the on-device diagnostics after a failed boot. Device must be in TWRP.
#
# The fsck is not optional: halium-boot resizes the userdata filesystem on every
# boot, and after a forced power-off the partition refuses to mount with an I/O
# error until it is checked.
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$HERE/logs/$(date +%Y%m%d-%H%M%S)}"

adb wait-for-device
adb shell 'mountpoint -q /data || { e2fsck -fy /dev/block/by-name/userdata >/dev/null 2>&1; mkdir -p /data; mount -t ext4 /dev/block/by-name/userdata /data; }'

mkdir -p "$OUT"
adb pull /data/system-data/var/log/ut-debug "$OUT/ut-debug" 2>&1 | tail -1
adb pull /data/system-data/var/log/lightdm "$OUT/lightdm" 2>&1 | tail -1
adb pull /sys/fs/pstore/console-ramoops-0 "$OUT/ramoops.txt" 2>&1 | tail -1 || echo "no pstore (clean shutdown)"

echo
echo "== состояние оболочки"
grep -hE "EGL|graphics platform|Failed to acquire|host socket" "$OUT"/ut-debug/lomiri.log "$OUT"/lightdm/seat0-greeter.log 2>/dev/null | tail -10 || true
echo
echo "-> $OUT"
