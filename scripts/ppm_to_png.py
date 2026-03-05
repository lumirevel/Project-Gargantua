#!/usr/bin/env python3
import argparse
import struct
import zlib


def chunk(chunk_type: bytes, payload: bytes) -> bytes:
    crc = zlib.crc32(chunk_type + payload) & 0xFFFFFFFF
    return struct.pack(">I", len(payload)) + chunk_type + payload + struct.pack(">I", crc)


def read_ppm(path: str) -> tuple[int, int, bytes]:
    with open(path, "rb") as f:
        magic = f.readline().strip()
        if magic != b"P6":
            raise ValueError("expected P6 PPM")
        line = f.readline()
        while line.startswith(b"#"):
            line = f.readline()
        w, h = map(int, line.strip().split())
        maxv = int(f.readline().strip())
        if maxv != 255:
            raise ValueError("expected max value 255")
        data = f.read()
    if len(data) != w * h * 3:
        raise ValueError("unexpected pixel data size")
    return w, h, data


def write_png(path: str, w: int, h: int, rgb: bytes) -> None:
    raw = bytearray()
    row_bytes = w * 3
    for y in range(h):
        raw.append(0)
        start = y * row_bytes
        raw.extend(rgb[start:start + row_bytes])
    compressed = zlib.compress(bytes(raw), level=6)
    ihdr = struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)
    blob = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", compressed) + chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(blob)


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--input", required=True)
    p.add_argument("--output", required=True)
    args = p.parse_args()
    w, h, rgb = read_ppm(args.input)
    write_png(args.output, w, h, rgb)


if __name__ == "__main__":
    main()
