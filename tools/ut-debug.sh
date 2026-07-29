#!/bin/sh
# Black-box recorder for a port that cannot be shelled into: no working adb, no
# RNDIS on the host. Runs once per boot, dumps everything needed to tell why
# the graphics stack did not come up, then the image is read back from TWRP.
#
# Output: /var/log/ut-debug/  (persisted in /data/system-data/var/log/ut-debug)
set -x

OUT=/var/log/ut-debug
mkdir -p "$OUT"
exec >"$OUT/collect.log" 2>&1

date

# Kernel ring buffer: panel, DSI, SDE and binder messages live here.
dmesg > "$OUT/dmesg.txt"

# The Android container's own log — the only place the composer HAL reports.
if command -v lxc-attach >/dev/null; then
    lxc-attach -n android -- /system/bin/logcat -d -v threadtime > "$OUT/logcat.txt" 2>&1
    lxc-attach -n android -- /system/bin/getprop > "$OUT/getprop.txt" 2>&1
    lxc-attach -n android -- /system/bin/lshal > "$OUT/lshal.txt" 2>&1
    lxc-attach -n android -- /system/bin/ps -A > "$OUT/android-ps.txt" 2>&1
fi

lxc-ls -f > "$OUT/lxc.txt" 2>&1

# The environment of the *running* shell process, straight from the kernel.
# Settles arguments about whether MIR_SERVER_HOST_SOCKET, MIR_SOCKET or
# LD_PRELOAD actually reach lomiri, instead of inferring it from unit files.
for pid in $(pgrep -f "bin/lomiri" 2>/dev/null); do
    {
        echo "=== pid $pid: $(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null)"
        tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null | sort
        echo
    } >> "$OUT/lomiri-environ.txt" 2>&1
done

# The greeter's own stderr: it exits 1 and systemd keeps the output in its unit
# journal, which the plain log files do not carry.
journalctl -b --no-pager -u lomiri-full-greeter > "$OUT/greeter.txt" 2>&1
journalctl -b --no-pager -u lightdm > "$OUT/lightdm-unit.txt" 2>&1
journalctl -b --no-pager -p warning > "$OUT/journal-warnings.txt" 2>&1
cp -a /var/log/lightdm "$OUT/lightdm-logs" 2>&1
systemctl --no-pager --failed > "$OUT/failed-units.txt" 2>&1
systemctl --no-pager status lightdm > "$OUT/lightdm-status.txt" 2>&1

# Mir handover: the greeter must connect to the system compositor's socket as a
# client. If it cannot, qtmir falls back to driving the display itself and dies
# with "must have at least EGL 1.4", because the compositor already owns it.
{
    echo "--- sockets"
    ls -l /run/mir_socket /run/lomiri_socket /run/user/*/mir_socket 2>&1
    echo "--- who owns them"
    id lightdm 2>&1; id phablet 2>&1
    echo "--- greeter unit environment"
    systemctl show lomiri-full-greeter -p Environment -p ExecStart 2>&1
    echo "--- session wrapper"
    cat /usr/share/ubuntu-touch-session/lsc-wrapper 2>&1
    echo "--- mir platforms present"
    ls -l /usr/lib/*/mir/client-platform/ /usr/lib/*/mir/server-platform/ 2>&1
    echo "--- ubuntu-touch-session.d"
    cat /etc/ubuntu-touch-session.d/android.conf 2>&1
} > "$OUT/mir.txt"

# Display side: does the kernel expose a panel at all?
{
    echo "--- /sys/class/backlight"
    ls -l /sys/class/backlight/ 2>&1
    for f in /sys/class/backlight/*/*; do
        echo "$f = $(cat "$f" 2>&1)"
    done
    echo "--- /sys/class/drm"
    ls -l /sys/class/drm/ 2>&1
    for s in /sys/class/drm/*/status; do
        echo "$s = $(cat "$s" 2>&1)"
    done
    echo "--- /dev/graphics /dev/dri"
    ls -l /dev/graphics/ /dev/dri/ 2>&1
    echo "--- binderfs"
    ls -l /dev/binderfs/ 2>&1
} > "$OUT/display.txt"

sync
