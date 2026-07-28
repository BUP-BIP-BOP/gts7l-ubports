#!/bin/bash
# Build a vbmeta image with both AVB flags set (3 = HASHTREE_DISABLED plus
# VERIFICATION_DISABLED). The Samsung port that boots on this family ships 3;
# flags=2 alone left the device stuck at the splash.
# Samsung SM8250 bootloaders refuse unsigned boot images unless this is flashed,
# and single-partition heimdall flashes on this family commit unreliably unless
# --VBMETA is part of the same command.
set -euo pipefail

WORK="${TMPDIR:-/tmp}/avb-gts7l"
mkdir -p "$WORK"

if [ ! -x "$WORK/avb/avbtool.py" ]; then
    git clone --depth=1 https://android.googlesource.com/platform/external/avb "$WORK/avb"
fi

python3 "$WORK/avb/avbtool.py" make_vbmeta_image \
    --flags 3 \
    --padding_size 4096 \
    --output vbmeta-disabled.img

ls -l vbmeta-disabled.img
echo "Flash with: heimdall flash --VBMETA vbmeta-disabled.img --no-reboot"
