#!/usr/bin/env python3
import argparse
import csv
import json
from pathlib import Path
from typing import Dict, Tuple

import numpy as np

C = 299792458.0
G = 6.67430e-11
M_BH = 1.0e35
RS = 2.0 * G * M_BH / (C * C)

COLLISION_DTYPE_V5 = np.dtype(
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


def load_meta(meta_path: Path) -> Dict:
    if not meta_path.exists():
        raise FileNotFoundError(f"meta file not found: {meta_path}")
    with meta_path.open("r", encoding="utf-8") as f:
        return json.load(f)


def infer_dims(meta: Dict, width: int, height: int) -> Tuple[int, int]:
    if width > 0 and height > 0:
        return width, height
    mw = int(meta.get("width", 0))
    mh = int(meta.get("height", 0))
    if mw <= 0 or mh <= 0:
        raise ValueError("width/height are required when meta does not include dimensions")
    return mw, mh


def compute_gfactor_legacy(v: np.ndarray, d: np.ndarray) -> Tuple[np.ndarray, np.ndarray]:
    v_norm = np.linalg.norm(v, axis=1)
    d_norm = np.linalg.norm(d, axis=1)
    dot_vd = np.einsum("ij,ij->i", v, d)
    beta = np.clip(v_norm / C, 0.0, 0.999999)
    gamma = 1.0 / np.sqrt(np.maximum(1.0 - beta * beta, 1e-12))
    cos_theta = dot_vd / np.maximum(v_norm * d_norm, 1e-30)
    cos_theta = np.clip(cos_theta, -1.0, 1.0)
    delta = 1.0 / np.maximum(gamma * (1.0 + beta * cos_theta), 1e-9)

    r_emit = (G * M_BH) / np.maximum(v_norm * v_norm, 1e-30)
    r_emit = np.maximum(r_emit, RS * 1.0001)
    g_gr = np.sqrt(np.clip(1.0 - RS / r_emit, 1e-8, 1.0))
    g_total = np.clip(delta * g_gr, 1e-4, 1e4)
    return g_total.astype(np.float32), r_emit.astype(np.float32)


def main() -> None:
    p = argparse.ArgumentParser(description="Export stage-3 bridge arrays from collisions.bin")
    p.add_argument("--input", required=True, help="collisions.bin path")
    p.add_argument("--meta", default="", help="metadata JSON path (default: <input>.json)")
    p.add_argument("--output", default="", help="output npz path (default: <input>.stage3.npz)")
    p.add_argument("--csv", default="", help="optional CSV output path")
    p.add_argument("--width", type=int, default=0, help="override width")
    p.add_argument("--height", type=int, default=0, help="override height")
    p.add_argument("--include-miss", action="store_true", help="include miss pixels too")
    args = p.parse_args()

    input_path = Path(args.input).expanduser().resolve()
    meta_path = Path(args.meta).expanduser().resolve() if args.meta else Path(str(input_path) + ".json")
    output_path = Path(args.output).expanduser().resolve() if args.output else Path(str(input_path) + ".stage3.npz")

    meta = load_meta(meta_path)
    width, height = infer_dims(meta, args.width, args.height)
    total = width * height

    stride_meta = int(meta.get("collisionStride", COLLISION_DTYPE_V5.itemsize))
    if stride_meta != COLLISION_DTYPE_V5.itemsize:
        raise ValueError(f"unsupported collisionStride={stride_meta}; expected {COLLISION_DTYPE_V5.itemsize}")

    raw_size = input_path.stat().st_size
    expected_size = total * COLLISION_DTYPE_V5.itemsize
    byte_offset = 0
    if raw_size == expected_size:
        byte_offset = 0
    elif raw_size == expected_size * 2:
        # Backward compatibility for old gpu-full-compose dumps where bytes were appended
        # after truncate without rewinding the file cursor.
        byte_offset = expected_size
        print(
            f"warning: detected doubled collision payload ({raw_size} bytes); "
            f"using trailing {expected_size} bytes"
        )
    else:
        raise ValueError(f"size mismatch: got {raw_size}, expected {expected_size}")

    rec = np.memmap(
        input_path,
        dtype=COLLISION_DTYPE_V5,
        mode="r",
        shape=(total,),
        offset=byte_offset,
    )
    hit_mask = rec["hit"] != 0
    if args.include_miss:
        sel = np.ones(total, dtype=np.bool_)
    else:
        sel = hit_mask

    idx = np.nonzero(sel)[0].astype(np.int32)
    x = (idx % width).astype(np.int32)
    y = (idx // width).astype(np.int32)

    v = rec["v_disk"][sel].astype(np.float32)
    d = rec["direct_world"][sel].astype(np.float32)
    spectral = str(meta.get("spectralEncoding", "legacy_vectors"))
    if spectral == "gfactor_v1":
        g_factor = np.clip(v[:, 0], 1e-4, 1e4).astype(np.float32)
        r_emit_m = np.maximum(v[:, 1], RS * 1.0001).astype(np.float32)
        vr_ratio = np.clip(v[:, 2], -1.0, 1.0).astype(np.float32)
    else:
        g_factor, r_emit_m = compute_gfactor_legacy(v.astype(np.float64), d.astype(np.float64))
        vr_ratio = np.zeros_like(g_factor, dtype=np.float32)

    payload = {
        "pixel_index": idx,
        "x": x,
        "y": y,
        "hit": rec["hit"][sel].astype(np.uint8),
        "ct": rec["ct"][sel].astype(np.float32),
        "temperature": rec["T"][sel].astype(np.float32),
        "noise": rec["noise"][sel].astype(np.float32),
        "v_disk": v,
        "direct_world": d,
        "g_factor": g_factor,
        "r_emit_m": r_emit_m,
        "vr_ratio": vr_ratio,
        "emit_r_norm": rec["emit_r_norm"][sel].astype(np.float32),
        "emit_phi": rec["emit_phi"][sel].astype(np.float32),
        "emit_z_norm": rec["emit_z_norm"][sel].astype(np.float32),
    }
    np.savez_compressed(output_path, **payload)
    print(f"saved npz: {output_path} ({idx.size} samples)")

    if args.csv:
        csv_path = Path(args.csv).expanduser().resolve()
        with csv_path.open("w", newline="", encoding="utf-8") as f:
            w = csv.writer(f)
            w.writerow(
                [
                    "pixel_index",
                    "x",
                    "y",
                    "hit",
                    "ct",
                    "temperature",
                    "noise",
                    "g_factor",
                    "r_emit_m",
                    "vr_ratio",
                    "emit_r_norm",
                    "emit_phi",
                    "emit_z_norm",
                ]
            )
            for i in range(idx.size):
                w.writerow(
                    [
                        int(payload["pixel_index"][i]),
                        int(payload["x"][i]),
                        int(payload["y"][i]),
                        int(payload["hit"][i]),
                        float(payload["ct"][i]),
                        float(payload["temperature"][i]),
                        float(payload["noise"][i]),
                        float(payload["g_factor"][i]),
                        float(payload["r_emit_m"][i]),
                        float(payload["vr_ratio"][i]),
                        float(payload["emit_r_norm"][i]),
                        float(payload["emit_phi"][i]),
                        float(payload["emit_z_norm"][i]),
                    ]
                )
        print(f"saved csv: {csv_path}")


if __name__ == "__main__":
    main()
