#!/bin/bash
# Build the heimdall CLI for macOS (Apple Silicon included) into ./bin/heimdall.
#
# Two upstream problems are patched here:
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
git clone -q --depth=1 https://github.com/Benjamin-Dobell/Heimdall "$WORK"

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
