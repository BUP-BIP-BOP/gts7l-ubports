#!/bin/bash
# Pull os_version / os_patch_level / offsets out of the stock boot.img and show
# what to put in deviceinfo.
#
# Usage:  tools/inspect-stock-bootimg.sh AP_T875XXU*.tar.md5
#     or  tools/inspect-stock-bootimg.sh boot.img
set -euo pipefail

SRC="${1:?usage: $0 <AP tar | boot.img>}"
WORK="${TMPDIR:-/tmp}/gts7l-bootimg"
rm -rf "$WORK"; mkdir -p "$WORK"

if [[ "$SRC" == *.img ]]; then
    cp "$SRC" "$WORK/boot.img"
else
    echo "==> extracting boot.img from the AP tarball"
    tar -xf "$SRC" -C "$WORK" boot.img.lz4 2>/dev/null || tar -xf "$SRC" -C "$WORK" boot.img
    if [ -f "$WORK/boot.img.lz4" ]; then
        command -v lz4 >/dev/null || { echo "install lz4: brew install lz4"; exit 1; }
        lz4 -d "$WORK/boot.img.lz4" "$WORK/boot.img"
    fi
fi

[ -f "$WORK/unpack_bootimg.py" ] || curl -sL -o "$WORK/unpack_bootimg.py" \
    https://raw.githubusercontent.com/LineageOS/android_system_tools_mkbootimg/lineage-19.1/unpack_bootimg.py

python3 "$WORK/unpack_bootimg.py" --boot_img "$WORK/boot.img" --out "$WORK/out" | tee "$WORK/header.txt"

echo
echo "==> map into deviceinfo:"
awk '
/^os version:/        {printf "deviceinfo_bootimg_os_version=\"%s\"\n", $3}
/^os patch level:/    {printf "deviceinfo_bootimg_os_patch_level=\"%s\"\n", $4}
/^page size:/         {printf "deviceinfo_flash_pagesize=\"%s\"\n", $3}
/^kernel load address:/  {printf "deviceinfo_flash_offset_kernel=\"%s\"\n", $4}
/^ramdisk load address:/ {printf "deviceinfo_flash_offset_ramdisk=\"%s\"\n", $4}
/^kernel tags load address:/ {printf "deviceinfo_flash_offset_tags=\"%s\"\n", $5}
/^boot image header version:/ {printf "deviceinfo_bootimg_header_version=\"%s\"\n", $5}
' "$WORK/header.txt"

echo
echo "note: offsets printed by the tool are absolute (base + offset);"
echo "with deviceinfo_flash_offset_base=0x00000000 they can be copied verbatim."
