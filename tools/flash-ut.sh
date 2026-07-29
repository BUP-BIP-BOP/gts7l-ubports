#!/bin/bash
# Guided flashing of the Ubuntu Touch port onto SM-T875.
#
#   tools/flash-ut.sh check      — verify that every file is present and sane
#   tools/flash-ut.sh pit        — dump the partition table (device in Download Mode)
#   tools/flash-ut.sh recovery   — flash vbmeta + UBports recovery
#   tools/flash-ut.sh rootfs     — push ubuntu.img to /data (device in recovery, adb)
#   tools/flash-ut.sh kernel     — flash vbmeta + boot + dtbo
#   tools/flash-ut.sh all        — recovery, then rootfs, then kernel, with pauses
#
# Two things learned the hard way on this device, both encoded below:
#
#   * heimdall's own help: "--no-reboot causes the device to remain in download
#     mode. If you wish to perform another action whilst remaining in download
#     mode, then the following action must specify the --resume flag." Without
#     it the second command dies with "Failed to send handshake!" and looks like
#     a broken cable. The script tracks session state and adds --resume itself.
#
#   * a heimdall session that writes several partitions in one go failed here on
#     the second file with "Failed to confirm end of file transfer sequence",
#     and took the whole session down. So each partition is written by its own
#     invocation, with retries. Set MULTI=1 for the classic single command.
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$HERE"

HEIMDALL="${HEIMDALL:-$HERE/bin/heimdall}"
IMG_DIR="${IMG_DIR:-$HERE/out}"
RETRIES="${RETRIES:-3}"

BOOT="$IMG_DIR/boot.img"
DTBO="$IMG_DIR/dtbo.img"
RECOVERY="$IMG_DIR/recovery.img"
ROOTFS="$IMG_DIR/ubuntu.img"
# CI ships vbmeta next to the images; tools/make-vbmeta.sh writes it to the repo
# root. Prefer the build artifact so a stale local copy cannot be flashed.
if [ -f "$IMG_DIR/vbmeta-disabled.img" ]; then
    VBMETA="$IMG_DIR/vbmeta-disabled.img"
else
    VBMETA="$HERE/vbmeta-disabled.img"
fi

# LineageOS BoardConfig for gts7l
BOOT_MAX=71303168
RECOVERY_MAX=86888448
DTBO_MAX=10485760

# Set once the first command of a download-mode session has run.
SESSION_OPEN=0

red()  { printf '\033[31m%s\033[0m\n' "$*"; }
warn() { printf '\033[33m%s\033[0m\n' "$*"; }
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
    [ "${AUTO_CONFIRM:-}" = "1" ] && return 0
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

# Decompress out/ubuntu.img.zst if only the compressed artifact is present.
unpack_rootfs() {
    [ -f "$ROOTFS" ] && return 0
    if [ -f "$ROOTFS.zst" ]; then
        command -v zstd >/dev/null || { red "install zstd: brew install zstd"; exit 1; }
        info "decompressing $(basename "$ROOTFS.zst")"
        zstd -d -f "$ROOTFS.zst" -o "$ROOTFS"
    fi
}

# heimdall_write <PARTITION> <file> [<PARTITION> <file> ...]
# One invocation, --resume added automatically for anything but the first.
heimdall_write() {
    local args=() attempt=1
    while [ $# -gt 0 ]; do args+=("--$1" "$2"); shift 2; done

    while :; do
        local cmd=("$HEIMDALL" flash "${args[@]}" --no-reboot)
        [ "$SESSION_OPEN" = 1 ] && cmd+=(--resume)

        if "${cmd[@]}"; then
            SESSION_OPEN=1
            return 0
        fi

        # A failed session leaves the protocol wedged; --resume will not help
        # until the device re-enters Download Mode.
        SESSION_OPEN=0
        if [ "$attempt" -ge "$RETRIES" ]; then
            red "failed after $attempt attempts: ${args[*]}"
            cat <<'EOF'
If this was "Failed to send handshake": the download-mode session is wedged.
Power off (Power+Vol-Down ~10s), re-enter Download Mode and run the step again.

If this was "Failed to confirm end of file transfer sequence": the transfer
itself broke. Try another USB port or cable, ideally through a USB 2.0 hub.
EOF
            return 1
        fi
        attempt=$((attempt + 1))
        warn "retry $attempt/$RETRIES — re-enter Download Mode if the device rebooted, then press Enter"
        [ "${AUTO_CONFIRM:-}" = "1" ] || read -r _
    done
}

# Write partitions one invocation each (default) or all at once (MULTI=1).
flash_set() {
    if [ "${MULTI:-0}" = "1" ]; then
        heimdall_write "$@"
        return
    fi
    while [ $# -gt 0 ]; do
        info "writing $1"
        heimdall_write "$1" "$2" || return 1
        shift 2
    done
}

step_recovery() {
    need_heimdall
    check_file "$VBMETA" 0 && check_file "$RECOVERY" $RECOVERY_MAX
    download_mode_hint
    confirm "This overwrites the RECOVERY and VBMETA partitions."
    flash_set VBMETA "$VBMETA" RECOVERY "$RECOVERY"
    cat <<'EOF'

Now: unplug USB, hold Power+Vol-Down until the screen goes black, then
immediately hold Vol-Up+Power to land in recovery. Booting into Android first
would let stock restore its own recovery.
EOF
}

step_rootfs() {
    unpack_rootfs
    check_file "$ROOTFS" 0
    info "waiting for adb in recovery"
    adb wait-for-device
    confirm "This wipes userdata on the tablet."

    adb shell 'mountpoint -q /data || mount /data' >/dev/null 2>&1 || true
    if ! adb shell 'mountpoint -q /data' >/dev/null 2>&1; then
        red "/data is not mounted in recovery — format it (ext4) first"
        exit 1
    fi

    local need avail
    need=$(( $(size_of "$ROOTFS") / 1024 ))
    avail=$(adb shell "df -k /data | tail -1 | awk '{print \$4}'" | tr -d '\r')
    if [ -n "$avail" ] && [ "$avail" -lt "$need" ]; then
        red "not enough space on /data: need ${need}K, have ${avail}K"
        exit 1
    fi

    adb shell 'rm -f /data/ubuntu.img'
    info "pushing $(size_of "$ROOTFS") bytes — several minutes"
    adb push "$ROOTFS" /data/ubuntu.img
    adb shell sync

    local local_sz remote_sz
    local_sz=$(size_of "$ROOTFS")
    remote_sz=$(adb shell "stat -c%s /data/ubuntu.img" | tr -d '\r')
    if [ "$local_sz" != "$remote_sz" ]; then
        red "size mismatch after push: local $local_sz, on device $remote_sz"
        exit 1
    fi
    info "ok, /data/ubuntu.img is $remote_sz bytes"
}

step_kernel() {
    need_heimdall
    check_file "$VBMETA" 0 && check_file "$BOOT" $BOOT_MAX && check_file "$DTBO" $DTBO_MAX
    download_mode_hint
    confirm "This overwrites the BOOT, DTBO and VBMETA partitions."
    flash_set VBMETA "$VBMETA" BOOT "$BOOT" DTBO "$DTBO"
    cat <<'EOF'

Unplug USB, hold Power. First boot takes 2-5 minutes.
If it hangs: telnet rescue on 192.168.2.15 over USB RNDIS — see docs/BRINGUP.md
EOF
}

case "${1:-check}" in

check)
    info "images in $IMG_DIR"
    rc=0
    check_file "$VBMETA"   0             || rc=1
    check_file "$BOOT"     $BOOT_MAX     || rc=1
    check_file "$DTBO"     $DTBO_MAX     || rc=1
    check_file "$RECOVERY" $RECOVERY_MAX || rc=1
    if [ ! -f "$ROOTFS" ] && [ -f "$ROOTFS.zst" ]; then
        printf '  ok  %-28s %s bytes (compressed)\n' "ubuntu.img.zst" "$(size_of "$ROOTFS.zst")"
    else
        check_file "$ROOTFS" 0 || rc=1
    fi
    echo
    if [ -x "$HEIMDALL" ]; then echo "  ok  heimdall $("$HEIMDALL" version)"; else red "MISSING  bin/heimdall"; rc=1; fi
    if command -v adb >/dev/null; then echo "  ok  adb $(adb version | head -1)"; else red "MISSING  adb"; rc=1; fi
    exit $rc
    ;;

pit)
    need_heimdall; download_mode_hint
    "$HEIMDALL" print-pit --no-reboot
    ;;

recovery) step_recovery ;;
rootfs)   step_rootfs ;;
kernel)   step_kernel ;;

all)
    step_recovery
    echo; read -r -p "press Enter once the tablet is in recovery and adb sees it: " _
    step_rootfs
    echo; read -r -p "press Enter once the tablet is back in Download Mode: " _
    step_kernel
    ;;

*)
    sed -n '2,9p' "$0"; exit 1
    ;;
esac
