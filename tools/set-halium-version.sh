#!/bin/bash
# Switch the port between Halium levels. The Halium version must match the
# Android API level of the vendor partition that stays on the device.
#
#   Android 11 (One UI 3.x) -> halium 11, API 30
#   Android 12 (One UI 4.x) -> halium 12, API 31
#   Android 13 (One UI 5.x) -> halium 13, API 33
#
# Usage: tools/set-halium-version.sh 11|12|13
set -euo pipefail

V="${1:?usage: $0 11|12|13}"

case "$V" in
    11) API=30; RADIO="1.4" ;;
    12) API=31; RADIO="1.5" ;;
    13) API=33; RADIO="1.6" ;;
    *)  echo "unsupported halium version: $V"; exit 1 ;;
esac

sed -i.bak "s|^deviceinfo_halium_version=.*|deviceinfo_halium_version=\"$V\"|" deviceinfo
sed -i.bak "s|^ApiLevel = .*|ApiLevel = $API|" overlay/system/opt/halium-overlay/etc/gbinder.conf
sed -i.bak "s|^radioInterface = .*|radioInterface = $RADIO|" overlay/system/etc/ofono/binder.d/qti.conf
sed -i.bak "s|interface=radio@[0-9.]*|interface=radio@$RADIO|" overlay/system/etc/ofono/ril_subscription.d/qti.conf
find . -name '*.bak' -delete

echo "halium=$V  gbinder ApiLevel=$API  radio HAL=$RADIO"
echo "Note: the clang pin in deviceinfo stays — it follows the kernel tree, not the Halium level."
