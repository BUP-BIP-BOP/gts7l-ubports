#!/bin/bash
# Collect every device-side value the port needs. Run with the tablet booted
# into STOCK Android with USB debugging enabled (or into TWRP — then some
# getprop values will be missing).
#
# Output: device-facts.txt  (attach it to the port repo, it is not secret)
set -uo pipefail

OUT="device-facts.txt"
adb wait-for-device

{
    echo "# collected $(date -u +%FT%TZ)"

    echo -e "\n## identity"
    adb shell getprop | grep -E "ro\.(product|build\.version|boot\.(hw_rev|bootloader|revision)|vendor\.build)" | sort

    echo -e "\n## board revision -> selects kona-sec-gts7l-<region>-overlay-rNN.dtbo"
    adb shell getprop ro.boot.hw_rev
    adb shell getprop ro.boot.em.model
    adb shell getprop ro.csc.sales_code

    echo -e "\n## radio HAL version -> ofono qti.conf radioInterface"
    adb shell 'lshal 2>/dev/null | grep -i radio' || echo "(lshal unavailable, run from stock)"

    echo -e "\n## backlight / leds sysfs -> gts7l.yaml"
    adb shell 'ls /sys/class/backlight/ 2>/dev/null'
    adb shell 'ls /sys/class/leds/ 2>/dev/null'

    echo -e "\n## input devices -> touch, s-pen, pogo keyboard"
    adb shell 'cat /proc/bus/input/devices 2>/dev/null'

    echo -e "\n## loaded modules -> overlay/system/etc/modules-load.d/gts7l.conf"
    adb shell 'lsmod 2>/dev/null'

    echo -e "\n## partitions by name"
    adb shell 'ls -l /dev/block/by-name/ 2>/dev/null'

    echo -e "\n## sound cards"
    adb shell 'cat /proc/asound/cards 2>/dev/null'
} > "$OUT" 2>&1

echo "wrote $OUT"
grep -E "ro.build.version.release|ro.boot.hw_rev" "$OUT" || true
