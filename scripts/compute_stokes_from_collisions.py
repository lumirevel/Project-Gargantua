#!/usr/bin/env python3
import argparse
import json
import math
import zlib
import struct
from pathlib import Path

import numpy as np


COLLISION_DTYPE_V6 = np.dtype(
    [
        ("hit", "<u4"),
        ("ct", "<f4"),
        ("T", "<f4"),
        ("_pad0", "V4"),
        ("v_disk", "<f4", (3,)),
        ("_pad1", "V4"),
        ("direct_world", "<f4", (3,)),
        ("_pad2", "V4"),
        ("noise", "<f4"),
        ("emit_r_norm", "<f4"),
        ("emit_phi", "<f4"),
        ("emit_z_norm", "<f4"),
    ]
)


def write_png(path: Path, img: np.ndarray) -> None:
    h, w, c = img.shape
    if c != 3:
        raise ValueError("PNG writer expects RGB image")
    rows = [b"\x00" + img[y].tobytes() for y in range(h)]
    raw = b"".join(rows)
    compressed = zlib.compress(raw, level=6)

    def chunk(tag: bytes, payload: bytes) -> bytes:
        crc = zlib.crc32(tag + payload) & 0xFFFFFFFF
        return struct.pack(">I", len(payload)) + tag + payload + struct.pack(">I", crc)

    ihdr = struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)
    png = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", compressed)
        + chunk(b"IEND", b"")
    )
    with path.open("wb") as f:
        f.write(png)


def load_meta(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as f:
        data = json.load(f)
    if not isinstance(data, dict):
        raise ValueError("meta JSON must be an object")
    return data


def main() -> None:
    p = argparse.ArgumentParser(description="Compute approximate Stokes I/Q/U diagnostics from collision buffer.")
    p.add_argument("--input", required=True, help="collisions.bin path")
    p.add_argument("--meta", required=True, help="collisions.bin.json path")
    p.add_argument("--output-json", required=True, help="output JSON path")
    p.add_argument("--output-png", default="", help="optional polarization fraction PNG path")
    p.add_argument("--pol-frac", type=float, default=0.25, help="intrinsic polarization fraction [0..1]")
    p.add_argument("--faraday", type=float, default=1.0, help="Faraday depolarization strength")
    p.add_argument("--pitch-deg", type=float, default=10.0, help="magnetic pitch angle in degrees")
    args = p.parse_args()

    bin_path = Path(args.input).expanduser().resolve()
    meta_path = Path(args.meta).expanduser().resolve()
    out_json = Path(args.output_json).expanduser().resolve()
    out_png = Path(args.output_png).expanduser().resolve() if args.output_png else None

    meta = load_meta(meta_path)
    width = int(meta.get("width", 0))
    height = int(meta.get("height", 0))
    if width <= 0 or height <= 0:
        raise ValueError("invalid width/height in meta")

    total = width * height
    expected = total * COLLISION_DTYPE_V6.itemsize
    actual = bin_path.stat().st_size
    if actual == expected:
        offset = 0
    elif actual == expected * 2:
        offset = expected
    else:
        raise ValueError(f"collision size mismatch: got {actual}, expected {expected} or {expected * 2}")

    rec = np.memmap(bin_path, dtype=COLLISION_DTYPE_V6, mode="r", shape=(total,), offset=offset)
    hit = rec["hit"] != 0
    hit_count = int(np.count_nonzero(hit))
    if hit_count == 0:
        result = {
            "width": width,
            "height": height,
            "hit_count": 0,
            "stokes_sum": {"I": 0.0, "Q": 0.0, "U": 0.0, "V": 0.0},
            "mean_pol_fraction": 0.0,
            "max_pol_fraction": 0.0,
        }
        out_json.parent.mkdir(parents=True, exist_ok=True)
        with out_json.open("w", encoding="utf-8") as f:
            json.dump(result, f, ensure_ascii=False, indent=2, sort_keys=True)
        print(f"STOKES_REPORT {out_json}")
        return

    rphi = rec["emit_phi"][hit].astype(np.float64)
    z_norm = rec["emit_z_norm"][hit].astype(np.float64)
    T = np.maximum(rec["T"][hit].astype(np.float64), 1.0)
    g = np.clip(rec["v_disk"][hit][:, 0].astype(np.float64), 1e-4, 1e4)
    d = rec["direct_world"][hit].astype(np.float64)
    noise = np.clip(rec["noise"][hit].astype(np.float64), 0.0, 1.0)

    d_norm = np.linalg.norm(d, axis=1)
    n = d / np.maximum(d_norm[:, None], 1e-30)

    pitch = math.radians(float(args.pitch_deg))
    cp = math.cos(pitch)
    sp = math.sin(pitch)
    e_phi = np.stack([-np.sin(rphi), np.cos(rphi), np.zeros_like(rphi)], axis=1)
    e_z = np.stack([np.zeros_like(rphi), np.zeros_like(rphi), np.ones_like(rphi)], axis=1)
    b = cp * e_phi + sp * np.sign(z_norm)[:, None] * e_z
    b_norm = np.linalg.norm(b, axis=1)
    b = b / np.maximum(b_norm[:, None], 1e-30)

    b_proj = b - np.sum(b * n, axis=1, keepdims=True) * n
    bp_norm = np.linalg.norm(b_proj, axis=1)
    valid = bp_norm > 1e-9

    ex = np.array([1.0, 0.0, 0.0], dtype=np.float64)
    ey = np.array([0.0, 1.0, 0.0], dtype=np.float64)
    e_pol = np.cross(n, b_proj)
    e_pol = e_pol / np.maximum(np.linalg.norm(e_pol, axis=1, keepdims=True), 1e-30)
    x = np.sum(e_pol * ex[None, :], axis=1)
    y = np.sum(e_pol * ey[None, :], axis=1)
    chi = np.arctan2(y, x)

    I = np.power(T * g, 4.0) * np.power(g, 3.0)
    pol_frac = np.clip(float(args.pol_frac), 0.0, 1.0)
    faraday = max(0.0, float(args.faraday))
    mu = np.abs(n[:, 2])
    depol = np.exp(-faraday * (0.35 + 0.65 * noise) / np.maximum(mu, 0.08))
    p_eff = pol_frac * depol
    p_eff *= valid.astype(np.float64)

    Q = p_eff * I * np.cos(2.0 * chi)
    U = p_eff * I * np.sin(2.0 * chi)
    V = np.zeros_like(I)

    p_map_hit = np.sqrt(Q * Q + U * U) / np.maximum(I, 1e-30)
    mean_p = float(np.mean(p_map_hit))
    max_p = float(np.max(p_map_hit))

    result = {
        "width": width,
        "height": height,
        "hit_count": hit_count,
        "pol_frac_input": pol_frac,
        "faraday_input": faraday,
        "pitch_deg_input": float(args.pitch_deg),
        "stokes_sum": {
            "I": float(np.sum(I)),
            "Q": float(np.sum(Q)),
            "U": float(np.sum(U)),
            "V": float(np.sum(V)),
        },
        "mean_pol_fraction": mean_p,
        "max_pol_fraction": max_p,
    }
    out_json.parent.mkdir(parents=True, exist_ok=True)
    with out_json.open("w", encoding="utf-8") as f:
        json.dump(result, f, ensure_ascii=False, indent=2, sort_keys=True)
    print(
        "STOKES "
        f"hits={hit_count} mean_p={mean_p:.6f} max_p={max_p:.6f} "
        f"I_sum={result['stokes_sum']['I']:.6e}"
    )
    print(f"STOKES_REPORT {out_json}")

    if out_png is not None:
        img = np.zeros((height, width), dtype=np.float64)
        idx = np.nonzero(hit)[0]
        yy = idx // width
        xx = idx - yy * width
        # Collisions are bottom-up, flip for final PNG orientation.
        img[height - 1 - yy, xx] = p_map_hit
        vmax = np.percentile(p_map_hit, 99.0) if p_map_hit.size > 0 else 1.0
        vmax = max(float(vmax), 1e-6)
        nimg = np.clip(img / vmax, 0.0, 1.0)
        rgb = np.zeros((height, width, 3), dtype=np.uint8)
        rgb[..., 0] = np.clip(255.0 * np.power(nimg, 0.65), 0.0, 255.0).astype(np.uint8)
        rgb[..., 1] = np.clip(255.0 * np.power(nimg, 0.90), 0.0, 255.0).astype(np.uint8)
        rgb[..., 2] = np.clip(255.0 * np.power(1.0 - nimg, 1.10), 0.0, 255.0).astype(np.uint8)
        out_png.parent.mkdir(parents=True, exist_ok=True)
        write_png(out_png, rgb)
        print(f"STOKES_PNG {out_png}")


if __name__ == "__main__":
    main()

