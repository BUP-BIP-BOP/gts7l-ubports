#!/bin/bash
# Guided flashing of the Ubuntu Touch port onto SM-T875.
#
#   tools/flash-ut.sh check      — verify that every file is present and sane
#   tools/flash-ut.sh pit        — dump the partition table (device in Download Mode)
#   tools/flash-ut.sh recovery   — flash vbmeta + UBports recovery
#   tools/flash-ut.sh rootfs     — push ubuntu.img to /data (device in recovery, adb)
#   tools/flash-ut.sh kernel     — flash vbmeta + boot + dtbo
#
# Every heimdall command includes --VBMETA on purpose: single-image flashes on
# Samsung SM8250 commit unreliably.
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$HERE"

HEIMDALL="${HEIMDALL:-$HERE/bin/heimdall}"
IMG_DIR="${IMG_DIR:-$HERE/out}"

BOOT="$IMG_DIR/boot.img"
DTBO="$IMG_DIR/dtbo.img"
RECOVERY="$IMG_DIR/recovery.img"
ROOTFS="$IMG_DIR/ubuntu.img"
VBMETA="$HERE/vbmeta-disabled.img"

# LineageOS BoardConfig for gts7l
BOOT_MAX=71303168
RECOVERY_MAX=86888448
DTBO_MAX=10485760

red()  { printf '\033[31m%s\033[0m\n' "$*"; }
info() { printf '\033[36m==> %s\033[0m\n' "$*"; }

need_heimdall() {
    [ -x "$HEIMDALL" ] || { red "no heimdall at $HEIMDALL — run tools/build-heimdall.sh"; exit 1; }
}

size_of() { stat -f%z "$1" 2>/dev/null || stat -c%s "$1"; }

check_file() { # path, max_bytes (0 = no limit)
    local f="$1" max="$2"
    if [ ! -f "$f" ]; then red "MISSING  $f"; return 1; fi
    local s; s="$(size_of "$f")"
    if [ "$max" -gt 0 ] && [ "$s" -gt "$max" ]; then
        red "TOO BIG  $f ($s > $max)"; return 1
    fi
    printf '  ok  %-28s %s bytes\n' "$(basename "$f")" "$s"
}

confirm() {
    red "$1"
    read -r -p "type YES to continue: " a
    [ "$a" = "YES" ] || { echo "aborted"; exit 1; }
}

download_mode_hint() {
    cat <<'EOF'
Put the tablet into Download Mode:
  power off -> hold Vol-Down + Vol-Up -> plug in USB -> Vol-Up to confirm
EOF
}

case "${1:-check}" in

check)
    info "images in $IMG_DIR"
    rc=0
    check_file "$VBMETA"   0            || rc=1
    check_file "$BOOT"     $BOOT_MAX    || rc=1
    check_file "$DTBO"     $DTBO_MAX    || rc=1
    check_file "$RECOVERY" $RECOVERY_MAX || rc=1
    if [ -f "$ROOTFS.zst" ] && [ ! -f "$ROOTFS" ]; then
        echo "  note: $ROOTFS.zst not yet decompressed (zstd -d)"
    else
        check_file "$ROOTFS" 0 || rc=1
    fi
    echo
    [ -x "$HEIMDALL" ] && echo "  ok  heimdall $("$HEIMDALL" version)" || red "MISSING  bin/heimdall"
    command -v adb >/dev/null && echo "  ok  adb $(adb version | head -1)" || red "MISSING  adb"
    exit $rc
    ;;

pit)
    need_heimdall; download_mode_hint
    "$HEIMDALL" detect && "$HEIMDALL" print-pit --no-reboot
    ;;

recovery)
    need_heimdall
    check_file "$VBMETA" 0 && check_file "$RECOVERY" $RECOVERY_MAX
    download_mode_hint
    confirm "This overwrites the RECOVERY and VBMETA partitions."
    "$HEIMDALL" flash --VBMETA "$VBMETA" --RECOVERY "$RECOVERY" --no-reboot
    cat <<'EOF'

Now: unplug USB, hold Power+Vol-Down until the screen goes black, then
immediately hold Vol-Up+Power to land in recovery. Booting into Android first
would let stock restore its own recovery.
EOF
    ;;

rootfs)
    check_file "$ROOTFS" 0
    info "waiting for adb in recovery"
    adb wait-for-device
    confirm "This wipes userdata on the tablet."
    adb shell 'mount | grep -q " /data " || mount /data' || true
    adb shell 'rm -f /data/ubuntu.img'
    info "pushing $(size_of "$ROOTFS") bytes — this takes several minutes"
    adb push "$ROOTFS" /data/ubuntu.img
    adb shell sync
    adb shell 'ls -l /data/ubuntu.img'
    ;;

kernel)
    need_heimdall
    check_file "$VBMETA" 0 && check_file "$BOOT" $BOOT_MAX && check_file "$DTBO" $DTBO_MAX
    download_mode_hint
    confirm "This overwrites the BOOT, DTBO and VBMETA partitions."
    "$HEIMDALL" flash --VBMETA "$VBMETA" --BOOT "$BOOT" --DTBO "$DTBO" --no-reboot
    echo
    echo "Unplug USB, hold Power. First boot takes 2-5 minutes."
    echo "If it hangs: telnet rescue on 192.168.2.15 over USB RNDIS — see docs/BRINGUP.md"
    ;;

*)
    sed -n '2,12p' "$0"; exit 1
    ;;
esac
