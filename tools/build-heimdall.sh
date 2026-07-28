#!/bin/bash
# Build the heimdall CLI for macOS (Apple Silicon included) into ./bin/heimdall.
#
# Uses the amo13 fork, NOT upstream Benjamin-Dobell. Upstream 1.4.2 builds fine
# but dies on this device with
#     ERROR: Failed to send handshake!
# because it never resets the USB device before the handshake; the bulk write
# then times out with actual_length=0. Verified on SM-T875, macOS 27 arm64:
# upstream fails, the fork reaches "Session begun" and downloads the PIT.
#
# Two problems still need patching on top of the fork:
#   1. CMakeLists declares cmake_minimum_required 2.8.4, which CMake 4 refuses
#      -> -DCMAKE_POLICY_VERSION_MINIMUM=3.5
#   2. on macOS libusb is linked statically and pulls IOKit/CoreFoundation/
#      Security symbols that upstream never links -> "ld: symbol(s) not found"
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${TMPDIR:-/tmp}/heimdall-build"

command -v cmake >/dev/null || { echo "brew install cmake"; exit 1; }
[ -d /opt/homebrew/include/libusb-1.0 ] || [ -d /usr/local/include/libusb-1.0 ] || {
    echo "brew install libusb"; exit 1; }

rm -rf "$WORK"
git clone -q --depth=1 https://github.com/amo13/Heimdall "$WORK"

python3 - "$WORK/heimdall/CMakeLists.txt" <<'PATCH'
import sys
p = sys.argv[1]
s = open(p).read()
anchor = 'target_link_libraries(heimdall PRIVATE ${LIBUSB_LIBRARY})'
frameworks = '''
if(APPLE)
    find_library(IOKIT_LIBRARY IOKit)
    find_library(COREFOUNDATION_LIBRARY CoreFoundation)
    find_library(SECURITY_LIBRARY Security)
    target_link_libraries(heimdall PRIVATE ${IOKIT_LIBRARY} ${COREFOUNDATION_LIBRARY} ${SECURITY_LIBRARY} objc)
endif(APPLE)
'''
if 'IOKIT_LIBRARY' not in s:
    s = s.replace(anchor, anchor + '\n' + frameworks)
open(p, 'w').write(s)
PATCH

cmake -S "$WORK" -B "$WORK/build" \
    -DDISABLE_FRONTEND=ON \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 >/dev/null

make -C "$WORK/build" -j"$(sysctl -n hw.ncpu)" >/dev/null

mkdir -p "$HERE/bin"
cp "$WORK/build/bin/heimdall" "$HERE/bin/heimdall"
"$HERE/bin/heimdall" version
echo "-> $HERE/bin/heimdall"
