#!/bin/bash
# Wrapper around the UBports generic adaptation build tools.
# Produces out/boot.img, out/dtbo.img and out/ubuntu.img (the rootfs).
set -xe

[ -d build ] || git clone --depth=1 \
    https://gitlab.com/ubports/porting/community-ports/halium-generic-adaptation-build-tools build

./build/build.sh -b workdir "$@"

DEVICE="$(. ./deviceinfo && echo "$deviceinfo_codename")"

# tarball name is device_<codename>.tar.xz or device_<codename>_usrmerge.tar.xz
# depending on the tools revision
TARBALL="$(ls out/device_${DEVICE}*.tar.xz | head -n1)"

./build/prepare-fake-ota.sh "$TARBALL" ota
./build/system-image-from-ota.sh ota/ubuntu_command out
mv out/rootfs.img out/ubuntu.img
