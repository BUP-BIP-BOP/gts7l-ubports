#!/bin/bash
# Add an AVB hash footer to boot.img and recovery.img.
#
# Samsung's ABL on sm8250 parses the AVB footer of the image it is about to
# boot even when verification is disabled in vbmeta. Images straight out of the
# adaptation build tools carry no footer, and the device stops at the Samsung
# splash: no kernel, no USB, no console. The working Droidian ports for this
# family (T870/T970) sign with the AOSP test key and a large rollback index,
# and that is what is reproduced here.
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$HERE"

IMG_DIR="${IMG_DIR:-$HERE/out}"
WORK="${TMPDIR:-/tmp}/avb-gts7l"
AVBTOOL="$WORK/avb/avbtool.py"
KEY="${KEY:-$WORK/avb/test/data/testkey_rsa4096.pem}"

# Partition sizes from the LineageOS BoardConfig for gts7l, matching the PIT.
BOOT_PARTITION_SIZE=71303168
RECOVERY_PARTITION_SIZE=86888448
# Same value the T870/T970 ports use: high enough to satisfy any stored index.
ROLLBACK_INDEX=1900000000

[ -f "$AVBTOOL" ] || {
    mkdir -p "$WORK"
    git clone --depth=1 https://android.googlesource.com/platform/external/avb "$WORK/avb"
}

sign() { # image partition_name partition_size
    local img="$1" name="$2" size="$3"
    [ -f "$img" ] || { echo "missing $img"; return 1; }

    python3 "$AVBTOOL" erase_footer --image "$img" 2>/dev/null || true
    python3 "$AVBTOOL" add_hash_footer \
        --image "$img" \
        --partition_name "$name" \
        --partition_size "$size" \
        --algorithm SHA256_RSA4096 \
        --key "$KEY" \
        --rollback_index "$ROLLBACK_INDEX"

    echo "signed $(basename "$img") as '$name' ($(stat -f%z "$img" 2>/dev/null || stat -c%s "$img") bytes)"
    python3 "$AVBTOOL" info_image --image "$img" | grep -E "Footer version|Image Size|Partition Name|Algorithm|Rollback Index" | sed 's/^/    /'
}

sign "$IMG_DIR/boot.img"     boot     "$BOOT_PARTITION_SIZE"
sign "$IMG_DIR/recovery.img" recovery "$RECOVERY_PARTITION_SIZE"
