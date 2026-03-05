#!/usr/bin/env python3
import argparse
import json
from pathlib import Path
from typing import Dict, Optional, Tuple

import numpy as np


COLLISION_DTYPE = np.dtype(
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
        ("_pad3", "V12"),
    ]
)


def parse_xy(raw: str) -> Tuple[int, int]:
    parts = [p.strip() for p in raw.split(",")]
    if len(parts) != 2:
        raise ValueError(f"pixel format must be x,y: {raw}")
    x = int(parts[0])
    y = int(parts[1])
    return x, y


def load_dims(width: int, height: int, meta_path: str) -> Tuple[int, int]:
    if meta_path:
        with open(meta_path, "r", encoding="utf-8") as f:
            meta = json.load(f)
        mw = int(meta.get("width", 0))
        mh = int(meta.get("height", 0))
        if mw > 0 and mh > 0:
            return mw, mh
    if width <= 0 or height <= 0:
        raise ValueError("width/height must be provided if --meta is missing or incomplete")
    return width, height


def load_hit_map(collisions_path: str, width: int, height: int) -> np.ndarray:
    total = width * height
    mem = np.memmap(collisions_path, dtype=COLLISION_DTYPE, mode="r", shape=(total,))
    hits = (mem["hit"] != 0).reshape(height, width)
    return np.asarray(hits, dtype=np.bool_)


def edge_hit_mask(hit: np.ndarray) -> np.ndarray:
    p = np.pad(hit, ((1, 1), (1, 1)), mode="constant", constant_values=False)
    center = p[1:-1, 1:-1]
    neigh_all = (
        p[:-2, :-2]
        & p[:-2, 1:-1]
        & p[:-2, 2:]
        & p[1:-1, :-2]
        & p[1:-1, 2:]
        & p[2:, :-2]
        & p[2:, 1:-1]
        & p[2:, 2:]
    )
    return center & (~neigh_all)


def choose_side_pixel(mask: np.ndarray, center_x: int, center_y: int, top: bool) -> Optional[Tuple[int, int]]:
    ys, xs = np.where(mask)
    if ys.size == 0:
        return None

    if top:
        side = ys < center_y
    else:
        side = ys > center_y
    ys = ys[side]
    xs = xs[side]
    if ys.size == 0:
        return None

    if top:
        dy = center_y - ys
    else:
        dy = ys - center_y
    dx = np.abs(xs - center_x)

    order = np.lexsort((dx, dy))
    idx = int(order[0])
    return int(xs[idx]), int(ys[idx])


def select_pixels(hit: np.ndarray, x_band_ratio: float = 0.30) -> Dict[str, Dict[str, int]]:
    h, w = hit.shape
    cx = w // 2
    cy = h // 2
    half_band = int(max(8, round(w * x_band_ratio * 0.5)))
    x0 = max(0, cx - half_band)
    x1 = min(w, cx + half_band)

    edge = edge_hit_mask(hit)
    band_edge = np.zeros_like(edge, dtype=np.bool_)
    band_edge[:, x0:x1] = edge[:, x0:x1]
    top_xy = choose_side_pixel(band_edge, cx, cy, top=True)
    bottom_xy = choose_side_pixel(band_edge, cx, cy, top=False)

    if top_xy is None or bottom_xy is None:
        band_hit = np.zeros_like(hit, dtype=np.bool_)
        band_hit[:, x0:x1] = hit[:, x0:x1]
        if top_xy is None:
            top_xy = choose_side_pixel(band_hit, cx, cy, top=True)
        if bottom_xy is None:
            bottom_xy = choose_side_pixel(band_hit, cx, cy, top=False)

    if top_xy is None or bottom_xy is None:
        raise RuntimeError("failed to auto-select top/bottom pixels from collisions")

    return {
        "top": {"x": int(top_xy[0]), "y": int(top_xy[1])},
        "bottom": {"x": int(bottom_xy[0]), "y": int(bottom_xy[1])},
        "band": {"x0": int(x0), "x1": int(x1), "center_x": int(cx), "center_y": int(cy)},
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Auto-select representative top/bottom lensed pixels.")
    parser.add_argument("--collisions", type=str, required=True, help="Path to collisions.bin")
    parser.add_argument("--meta", type=str, default="", help="Path to collisions.bin.json")
    parser.add_argument("--width", type=int, default=0)
    parser.add_argument("--height", type=int, default=0)
    parser.add_argument("--pixel-top", type=str, default="", help="Manual override: x,y")
    parser.add_argument("--pixel-bottom", type=str, default="", help="Manual override: x,y")
    parser.add_argument("--x-band-ratio", type=float, default=0.30)
    parser.add_argument("--out", type=str, default="", help="Optional JSON output path")
    args = parser.parse_args()

    width, height = load_dims(args.width, args.height, args.meta)
    hit = load_hit_map(args.collisions, width, height)
    picked = select_pixels(hit, x_band_ratio=max(0.05, min(0.9, args.x_band_ratio)))

    source_top = "auto"
    source_bottom = "auto"
    if args.pixel_top:
        x, y = parse_xy(args.pixel_top)
        picked["top"] = {"x": x, "y": y}
        source_top = "manual"
    if args.pixel_bottom:
        x, y = parse_xy(args.pixel_bottom)
        picked["bottom"] = {"x": x, "y": y}
        source_bottom = "manual"

    result = {
        "width": width,
        "height": height,
        "top": {**picked["top"], "source": source_top},
        "bottom": {**picked["bottom"], "source": source_bottom},
        "band": picked["band"],
    }

    if args.out:
        out_path = Path(args.out)
        out_path.parent.mkdir(parents=True, exist_ok=True)
        with open(out_path, "w", encoding="utf-8") as f:
            json.dump(result, f, indent=2, sort_keys=True)
        print(f"saved: {out_path}")

    print(json.dumps(result, indent=2, sort_keys=True))
    print(f"top=({result['top']['x']},{result['top']['y']}) source={source_top}")
    print(f"bottom=({result['bottom']['x']},{result['bottom']['y']}) source={source_bottom}")


if __name__ == "__main__":
    main()
