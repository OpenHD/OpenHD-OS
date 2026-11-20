#!/usr/bin/env python3
"""Generate the distribution's small GRUB artwork using only the Python stdlib."""
import math
import pathlib
import struct
import zlib


def png(path, width, height, pixel):
    def chunk(kind, content):
        return struct.pack(">I", len(content)) + kind + content + struct.pack(">I", zlib.crc32(kind + content))
    data = bytearray()
    for y in range(height):
        data.append(0)
        for x in range(width):
            data.extend(pixel(x, y))
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(data, 9)) + chunk(b"IEND", b""))


def main():
    base = pathlib.Path(__file__).parent / "overlay/usr/share/grub/themes/openhd"
    # background.png is the hand-composed OpenHD 3.0 boot artwork. Keep this
    # utility focused on the tiny monochrome menu icons and selection slices.
    for name in ("minimal", "desktop", "install", "advanced"):
        def icon(x, y):
            if name == "minimal":
                radius = math.hypot(x - 32, y - 32)
                lit = 23 < radius < 26 or (x < 31 and y < 31 and (12 < radius < 15 or 18 < radius < 21))
            elif name == "desktop":
                lit = (8 <= x <= 56 and (12 <= y <= 15 or 43 <= y <= 46)) or (12 <= y <= 46 and (8 <= x <= 11 or 53 <= x <= 56)) or (30 <= x <= 34 and 46 <= y <= 54) or (22 <= x <= 42 and 53 <= y <= 56)
            elif name == "install":
                lit = (29 <= x <= 35 and 8 <= y <= 37) or (25 <= y <= 44 and abs(x - 32) <= y - 24 and abs(x - 32) >= y - 31) or (10 <= x <= 54 and 52 <= y <= 56)
            else:
                radius = math.hypot(x - 32, y - 32)
                lit = 15 <= radius <= 23 and (x % 16 < 10 or y % 16 < 10)
            return (48, 197, 239, 255) if lit else (0, 0, 0, 0)
        png(base / "icons" / (name + ".png"), 64, 64, icon)
    # selected_*.png are hand-composed nine-slice panels with a cyan glow.


if __name__ == "__main__":
    main()
