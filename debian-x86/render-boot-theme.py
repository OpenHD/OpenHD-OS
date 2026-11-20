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
                play = 24 <= x <= 43 and abs(y - 32) <= (x - 24) * 0.72
                lit = 24 < radius < 28 or play
            elif name == "desktop":
                lit = (8 <= x <= 56 and (12 <= y <= 15 or 43 <= y <= 46)) or (12 <= y <= 46 and (8 <= x <= 11 or 53 <= x <= 56)) or (30 <= x <= 34 and 46 <= y <= 54) or (22 <= x <= 42 and 53 <= y <= 56)
            elif name == "install":
                shaft = 30 <= x <= 34 and 10 <= y <= 35
                head = 18 <= y <= 41 and abs(abs(x - 32) - (y - 18)) <= 2
                tray = (13 <= x <= 51 and 50 <= y <= 54) or (13 <= x <= 17 and 44 <= y <= 52) or (47 <= x <= 51 and 44 <= y <= 52)
                lit = shaft or head or tray
            else:
                radius = math.hypot(x - 32, y - 32)
                lit = 15 <= radius <= 23 and (x % 16 < 10 or y % 16 < 10)
            return (235, 246, 252, 255) if lit else (0, 0, 0, 0)
        png(base / "icons" / (name + ".png"), 64, 64, icon)
    # selected_*.png are hand-composed nine-slice panels with a cyan glow.


if __name__ == "__main__":
    main()
