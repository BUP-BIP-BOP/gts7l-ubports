#!/bin/sh
# Generate the device udev rules the graphical UI needs, exactly as the UBports
# porting guide prescribes for Halium 9+:
#
#   cat .../ueventd*.rc | grep ^/dev | awk '{ACTION=="add", KERNEL, OWNER, GROUP, MODE}'
#
# The rootfs ships /usr/lib/udev/rules.d/70-android.rules as an empty stub whose
# only content is a comment saying it "gets replaced by device-specific rules at
# run-time" — nothing in the image does that, so a port must. Without these
# rules the Android device nodes keep root:root ownership on the Ubuntu side and
# the shell cannot reach the GPU.
#
# Generating at boot rather than shipping a static file keeps the rules correct
# across stock firmware updates, which is where the vendor half comes from.
set -eu

OUT=/etc/udev/rules.d/70-gts7l.rules
CONTAINER=/var/lib/lxc/android/rootfs

sources=""
for f in "$CONTAINER"/ueventd*.rc "$CONTAINER"/etc/ueventd*.rc \
         "$CONTAINER"/system/etc/ueventd*.rc \
         /vendor/ueventd*.rc /vendor/etc/ueventd*.rc; do
    [ -f "$f" ] && sources="$sources $f"
done

if [ -z "$sources" ]; then
    echo "no ueventd files found; is the Android container mounted?" >&2
    exit 1
fi

# shellcheck disable=SC2086
cat $sources \
    | grep '^/dev' \
    | sed -e 's|^/dev/||' \
    | awk '{printf "ACTION==\"add\", KERNEL==\"%s\", OWNER=\"%s\", GROUP=\"%s\", MODE=\"%s\"\n", $1, $3, $4, $2}' \
    | sed -e 's/\r//' \
    | sort -u > "$OUT.new"

if [ ! -s "$OUT.new" ]; then
    rm -f "$OUT.new"
    echo "generated no rules from:$sources" >&2
    exit 1
fi

if ! cmp -s "$OUT.new" "$OUT" 2>/dev/null; then
    mv "$OUT.new" "$OUT"
    echo "wrote $(wc -l < "$OUT") rules to $OUT"
    udevadm control --reload-rules || true
    udevadm trigger --action=add || true
    udevadm settle --timeout=30 || true
else
    rm -f "$OUT.new"
fi
