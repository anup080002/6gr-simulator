#!/usr/bin/env python3
"""Write a PNG from raw RGB bytes using only Python stdlib."""

from __future__ import annotations

import binascii
import struct
import sys
import zlib
from pathlib import Path


def _chunk(kind: bytes, payload: bytes) -> bytes:
    crc = binascii.crc32(kind)
    crc = binascii.crc32(payload, crc) & 0xFFFFFFFF
    return struct.pack(">I", len(payload)) + kind + payload + struct.pack(">I", crc)


def write_png(raw_path: Path, png_path: Path, width: int, height: int) -> None:
    data = raw_path.read_bytes()
    expected = width * height * 3
    if len(data) != expected:
        raise ValueError(f"raw RGB byte count {len(data)} does not match {width}x{height}x3={expected}")
    scanlines = bytearray()
    row_bytes = width * 3
    for row in range(height):
        scanlines.append(0)
        start = row * row_bytes
        scanlines.extend(data[start:start + row_bytes])
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    png = b"\x89PNG\r\n\x1a\n" + _chunk(b"IHDR", ihdr) + _chunk(b"IDAT", zlib.compress(bytes(scanlines), 9)) + _chunk(b"IEND", b"")
    png_path.parent.mkdir(parents=True, exist_ok=True)
    png_path.write_bytes(png)


def main(argv: list[str]) -> int:
    if len(argv) != 5:
        print("usage: write_png_from_raw_rgb.py <raw.rgb> <out.png> <width> <height>", file=sys.stderr)
        return 2
    write_png(Path(argv[1]), Path(argv[2]), int(argv[3]), int(argv[4]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
