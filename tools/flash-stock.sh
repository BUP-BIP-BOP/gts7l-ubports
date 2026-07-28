#!/bin/bash
# Flash a full Samsung stock firmware (BL + AP + CP + CSC) with heimdall.
#
#   tools/flash-stock.sh prepare        unpack the tarballs into fw/unpacked/
#   tools/flash-stock.sh plan           show partition -> file mapping (no writes)
#   tools/flash-stock.sh flash [--go]   flash; without --go it only prints the command
#
# The mapping is derived from the device's own PIT: every PIT entry carries a
# "Flash Filename", and Samsung names the files inside the tarballs exactly that
# way, so file name -> partition name is a lookup, not a guess.
#
# DANGER: this writes bootloader partitions (XBL, ABL, TZ, AOP...). A failure
# part-way through that set leaves a device that no re-flash can recover.
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$HERE"

FW_DIR="${FW_DIR:-$HERE/SAMFW}"
UNPACK="${UNPACK:-$HERE/fw/unpacked}"
PIT_TXT="${PIT_TXT:-$HERE/fw/pit.txt}"
HEIMDALL="${HEIMDALL:-$HERE/bin/heimdall}"

# Partitions that are never part of a normal Odin flash, or that we refuse to
# touch: the GPT copies and the PIT itself.
SKIP_PARTITIONS="PIT PGPT0 PGPT1 PGPT2 PGPT3 SGPT0 SGPT1 SGPT2 SGPT3 MD5"

# Which tarballs to take files from. Default excludes BL: writing XBL/ABL/TZ/AOP
# is the only part of a stock flash that can brick the device beyond recovery,
# and it is not needed to put an Android 11 vendor into super.
# Set SCOPE="BL AP CP CSC" for the full Odin-equivalent flash.
SCOPE="${SCOPE:-AP CP CSC}"

# stdout: one file basename per line, for the tarballs in SCOPE
scope_files() {
    local t
    for t in $SCOPE; do
        for tarball in "$FW_DIR"/${t}_*.tar.md5; do
            [ -f "$tarball" ] || continue
            tar -tf "$tarball" | sed 's|\.lz4$||' | grep -v '/$'
        done
    done
}

info() { printf '\033[36m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[33m%s\033[0m\n' "$*"; }
red()  { printf '\033[31m%s\033[0m\n' "$*"; }

RETRIES="${RETRIES:-3}"
SESSION_OPEN=0

# One partition per invocation: a session that carried several partitions died
# here on the second file with "Failed to confirm end of file transfer
# sequence". --resume is required for every command after the first in the same
# download-mode session, otherwise heimdall reports "Failed to send handshake!".
write_partition() { # PARTITION file
    local part="$1" file="$2" attempt=1
    while :; do
        local cmd=("$HEIMDALL" flash "--$part" "$file" --no-reboot)
        [ "$SESSION_OPEN" = 1 ] && cmd+=(--resume)
        if "${cmd[@]}"; then
            SESSION_OPEN=1
            return 0
        fi
        SESSION_OPEN=0
        if [ "$attempt" -ge "$RETRIES" ]; then
            red "$part failed after $attempt attempts"
            return 1
        fi
        attempt=$((attempt + 1))
        warn "$part: retry $attempt/$RETRIES"
        sleep 3
    done
}

read_pit() {
    if [ ! -s "$PIT_TXT" ]; then
        info "downloading PIT from the device"
        mkdir -p "$(dirname "$PIT_TXT")"
        "$HEIMDALL" print-pit --no-reboot > "$PIT_TXT"
    fi
}

# stdout: "<flash filename>\t<partition name>"
pit_map() {
    python3 - "$PIT_TXT" <<'PY'
import re, sys
t = open(sys.argv[1]).read()
seen = set()
for e in re.split(r'--- Entry #\d+ ---', t)[1:]:
    d = dict(re.findall(r'^(.*?):\s*(.*)$', e, re.M))
    name = d.get('Partition Name', '').strip()
    fn   = d.get('Flash Filename', '').strip()
    if not name or not fn or fn.startswith('FOTA'):
        continue
    if fn in seen:      # XBL/XBL_CONFIG appear once per boot LUN
        continue
    seen.add(fn)
    print(f"{fn}\t{name}")
PY
}

case "${1:-plan}" in

prepare)
    mkdir -p "$UNPACK"
    shopt -s nullglob
    for tarball in "$FW_DIR"/{BL,AP,CP,CSC}_*.tar.md5; do
        info "unpacking $(basename "$tarball")"
        tar -xf "$tarball" -C "$UNPACK"
    done
    info "decompressing .lz4"
    for f in "$UNPACK"/*.lz4; do
        lz4 -d -q -f "$f" "${f%.lz4}" && rm -f "$f"
    done
    rm -rf "$UNPACK/meta-data"
    ls -lh "$UNPACK" | tail -n +2
    ;;

plan|flash)
    read_pit
    [ -d "$UNPACK" ] || { red "run '$0 prepare' first"; exit 1; }

    PARTS=()
    FILES=()
    ALLOWED=" $(scope_files | tr '\n' ' ') "
    info "scope: $SCOPE"
    printf '%-22s %-24s %s\n' PARTITION FILE SIZE
    while IFS=$'\t' read -r fn part; do
        case " $SKIP_PARTITIONS " in *" $part "*) continue ;; esac
        case "$ALLOWED" in *" $fn "*) ;; *) continue ;; esac
        f="$UNPACK/$fn"
        [ -f "$f" ] || continue
        sz=$(stat -f%z "$f" 2>/dev/null || stat -c%s "$f")
        printf '%-22s %-24s %s\n' "$part" "$fn" "$sz"
        PARTS+=("$part")
        FILES+=("$f")
    done < <(pit_map)

    echo
    echo "${#PARTS[@]} partitions"

    # ONLY=PART1,PART2 restricts the write to specific partitions, e.g. to
    # resume after a failure without redoing the multi-GB ones.
    if [ "${1:-}" = "flash" ]; then
        if [ "${2:-}" != "--go" ]; then
            echo
            echo "dry run. Re-run with:  $0 flash --go"
            echo "Each partition is written by its own heimdall invocation."
            exit 0
        fi
        red "About to write ${#PARTS[@]} partitions. Do not unplug."
        if [ "${AUTO_CONFIRM:-}" != "1" ]; then
            case "$SCOPE" in *BL*) red "SCOPE includes BL: an interruption during
XBL/ABL/TZ/AOP is unrecoverable." ;; esac
            read -r -p "type FLASH to proceed: " a
            [ "$a" = "FLASH" ] || { echo aborted; exit 1; }
        fi

        # MULTI=1: one heimdall invocation for everything. This device only
        # accepts a single write per Download Mode entry, so this is the only
        # shape that can flash a whole firmware without re-entering the mode
        # between partitions — at the cost of losing everything if one file
        # fails mid-way.
        if [ "${MULTI:-0}" = "1" ]; then
            ARGS=()
            for i in "${!PARTS[@]}"; do
                if [ -n "${ONLY:-}" ]; then
                    case ",$ONLY," in *",${PARTS[$i]},"*) ;; *) continue ;; esac
                fi
                ARGS+=("--${PARTS[$i]}" "${FILES[$i]}")
            done
            info "single session, $(( ${#ARGS[@]} / 2 )) partitions"
            exec "$HEIMDALL" flash "${ARGS[@]}" --no-reboot
        fi

        FAILED=()
        for i in "${!PARTS[@]}"; do
            part="${PARTS[$i]}"
            if [ -n "${ONLY:-}" ]; then
                case ",$ONLY," in *",$part,"*) ;; *) continue ;; esac
            fi
            info "[$((i + 1))/${#PARTS[@]}] $part"
            write_partition "$part" "${FILES[$i]}" || FAILED+=("$part")
        done

        echo
        if [ "${#FAILED[@]}" -gt 0 ]; then
            red "failed: ${FAILED[*]}"
            echo "Re-enter Download Mode and retry just those:"
            echo "  ONLY=$(IFS=,; echo "${FAILED[*]}") $0 flash --go"
            exit 1
        fi
        info "all ${#PARTS[@]} partitions written"
    fi
    ;;

*)
    sed -n '2,9p' "$0"; exit 1
    ;;
esac
