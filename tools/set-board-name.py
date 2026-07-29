#!/usr/bin/env python3
"""Write the 16-byte product/board field of an Android boot header.

Stock T875XXS5DXD1 carries "SRPTC18C005" there. Images produced by the
adaptation build tools leave the field zeroed, and Samsung's ABL stops at the
splash without handing control to the kernel. The Droidian port for this family
patches the same field, so match stock exactly.

Usage: set-board-name.py <boot.img> [board-name]
"""
import sys

img = sys.argv[1]
board = (sys.argv[2] if len(sys.argv) > 2 else "SRPTC18C005").encode()
if len(board) > 16:
    sys.exit("board name must fit in 16 bytes")

with open(img, "rb") as f:
    d = bytearray(f.read())

if d[:8] != b"ANDROID!":
    sys.exit(f"{img}: not an Android boot image")

d[48:64] = board.ljust(16, b"\x00")

with open(img, "wb") as f:
    f.write(bytes(d))

print(f"{img}: product field set to {board.decode()}")
