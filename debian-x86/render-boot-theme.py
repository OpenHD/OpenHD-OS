#!/usr/bin/env python3
"""Render crisp, antialiased OpenHD GRUB icons from simple vector geometry."""
import math
import pathlib


def png(path, width, height, pixel):
    import struct
    import zlib

    def chunk(kind, content):
        return struct.pack(">I", len(content)) + kind + content + struct.pack(">I", zlib.crc32(kind + content))

    data = bytearray()
    for y in range(height):
        data.append(0)
        for x in range(width):
            data.extend(pixel(x, y))
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(data, 9)) + chunk(b"IEND", b""))


def segment_distance(x, y, a, b):
    dx, dy = b[0] - a[0], b[1] - a[1]
    length = dx * dx + dy * dy
    t = max(0.0, min(1.0, ((x - a[0]) * dx + (y - a[1]) * dy) / length)) if length else 0.0
    return math.hypot(x - a[0] - t * dx, y - a[1] - t * dy)


def polygon_contains(x, y, points):
    inside = False
    j = len(points) - 1
    for i, (xi, yi) in enumerate(points):
        xj, yj = points[j]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi:
            inside = not inside
        j = i
    return inside


def main():
    base = pathlib.Path(__file__).parent / "overlay/usr/share/grub/themes/openhd/icons"
    scale = 4
    white = (239, 247, 252, 255)
    play = [(25, 22), (43, 32), (25, 42)]
    monitor = [(12, 13), (52, 13), (52, 43), (12, 43)]
    arrowhead = [(20, 29), (32, 41), (44, 29)]
    tray = [(13, 45), (13, 53), (51, 53), (51, 45)]
    gear = []
    for tooth in range(12):
        center = math.tau * tooth / 12
        for offset, radius in ((-15, 18), (-10, 23), (10, 23), (15, 18)):
            angle = center + math.radians(offset)
            gear.append((32 + math.cos(angle) * radius, 32 + math.sin(angle) * radius))

    def inside_line(x, y, points, thickness, closed=True):
        edges = len(points) if closed else len(points) - 1
        return any(segment_distance(x, y, points[i], points[(i + 1) % len(points)]) <= thickness / 2 for i in range(edges))

    def shape(name, x, y):
        radius = math.hypot(x - 32, y - 32)
        if name == "minimal":
            return abs(radius - 23) <= 1.8 or polygon_contains(x, y, play)
        if name == "desktop":
            return inside_line(x, y, monitor, 3.4) or segment_distance(x, y, (30, 43), (30, 49)) <= 1.7 or segment_distance(x, y, (34, 43), (34, 49)) <= 1.7 or segment_distance(x, y, (22, 51), (42, 51)) <= 1.7
        if name == "install":
            shaft = segment_distance(x, y, (32, 11), (32, 37)) <= 1.8
            return shaft or inside_line(x, y, arrowhead, 3.5, closed=False) or inside_line(x, y, tray, 3.2, closed=False)
        return inside_line(x, y, gear, 3.4) or abs(radius - 9) <= 2.2

    for name in ("minimal", "desktop", "install", "advanced"):
        def pixel(ix, iy, icon=name):
            coverage = 0
            for sy in range(scale):
                for sx in range(scale):
                    if shape(icon, (ix + (sx + .5) / scale) * 64 / 64, (iy + (sy + .5) / scale) * 64 / 64):
                        coverage += 1
            alpha = round(255 * coverage / (scale * scale))
            return (*white[:3], alpha if coverage else 0)
        png(base / f"{name}.png", 64, 64, pixel)


if __name__ == "__main__":
    main()
