#!/usr/bin/env python3
import argparse
import json
from pathlib import Path
from typing import Dict, Tuple

import numpy as np


def _load_npz(path: Path) -> Dict[str, np.ndarray]:
    data = np.load(path)
    return {k: data[k] for k in data.files}


def _load_csv(path: Path) -> Dict[str, np.ndarray]:
    arr = np.genfromtxt(path, delimiter=",", names=True)
    out: Dict[str, np.ndarray] = {}
    for name in arr.dtype.names or []:
        out[name] = np.asarray(arr[name])
    return out


def _pick(data: Dict[str, np.ndarray], *keys: str) -> np.ndarray:
    for k in keys:
        if k in data:
            return np.asarray(data[k], dtype=np.float64)
    raise KeyError(f"missing required field; tried {keys}")


def _pick_optional(data: Dict[str, np.ndarray], default: float, *keys: str) -> np.ndarray:
    for k in keys:
        if k in data:
            return np.asarray(data[k], dtype=np.float64)
    return np.full((len(next(iter(data.values()))),), default, dtype=np.float64)


def _aggregate_mean(values: np.ndarray, flat_idx: np.ndarray, n_cells: int) -> Tuple[np.ndarray, np.ndarray]:
    sums = np.bincount(flat_idx, weights=values, minlength=n_cells).astype(np.float64)
    counts = np.bincount(flat_idx, minlength=n_cells).astype(np.float64)
    out = np.zeros(n_cells, dtype=np.float64)
    nz = counts > 0
    out[nz] = sums[nz] / counts[nz]
    return out, counts


def _fill_holes(field: np.ndarray, counts: np.ndarray) -> np.ndarray:
    out = field.copy()
    h, w = out.shape
    global_med = float(np.median(out[counts > 0])) if np.any(counts > 0) else 0.0
    for y in range(h):
        row_mask = counts[y] > 0
        row_med = float(np.median(out[y, row_mask])) if np.any(row_mask) else global_med
        out[y, ~row_mask] = row_med
    return out


def _build_atlas(
    r_norm: np.ndarray,
    phi: np.ndarray,
    temp: np.ndarray,
    density: np.ndarray,
    vr_ratio: np.ndarray,
    vphi_scale: np.ndarray,
    width: int,
    height: int,
    r_min: float,
    r_max: float,
    r_warp: float,
) -> np.ndarray:
    r01 = (r_norm - r_min) / max(r_max - r_min, 1e-12)
    r01 = np.clip(r01, 0.0, 1.0)
    r01 = np.power(r01, r_warp)
    phi01 = (phi / (2.0 * np.pi)) % 1.0

    xb = np.clip((phi01 * (width - 1)).astype(np.int64), 0, width - 1)
    yb = np.clip((r01 * (height - 1)).astype(np.int64), 0, height - 1)
    flat = yb * width + xb
    n_cells = width * height

    t_flat, cnt = _aggregate_mean(temp, flat, n_cells)
    d_flat, _ = _aggregate_mean(density, flat, n_cells)
    vr_flat, _ = _aggregate_mean(vr_ratio, flat, n_cells)
    vp_flat, _ = _aggregate_mean(vphi_scale, flat, n_cells)

    cnt2 = cnt.reshape(height, width)
    t = _fill_holes(t_flat.reshape(height, width), cnt2)
    d = _fill_holes(d_flat.reshape(height, width), cnt2)
    vr = _fill_holes(vr_flat.reshape(height, width), cnt2)
    vp = _fill_holes(vp_flat.reshape(height, width), cnt2)

    atlas = np.zeros((height, width, 4), dtype=np.float32)
    atlas[..., 0] = np.clip(t, 0.05, 20.0).astype(np.float32)
    atlas[..., 1] = np.clip(d, 0.0, 1.0).astype(np.float32)
    atlas[..., 2] = np.clip(vr, -1.0, 1.0).astype(np.float32)
    atlas[..., 3] = np.clip(vp, 0.0, 4.0).astype(np.float32)
    return atlas


def main() -> None:
    ap = argparse.ArgumentParser(description="Build stage-3 disk atlas (float4 grid) from bridge samples")
    ap.add_argument("--input", required=True, help="input .npz or .csv")
    ap.add_argument("--output", required=True, help="output atlas .bin")
    ap.add_argument("--width", type=int, default=1024, help="atlas width (phi bins)")
    ap.add_argument("--height", type=int, default=512, help="atlas height (radial bins)")
    ap.add_argument("--r-min", type=float, default=1.0, help="minimum r/rs mapped to row 0")
    ap.add_argument("--r-max", type=float, default=9.0, help="maximum r/rs mapped to last row")
    ap.add_argument("--r-warp", type=float, default=1.0, help="radial mapping exponent (<1.0 = higher inner-ring resolution)")
    ap.add_argument("--density-source", choices=["density", "noise", "ones"], default="density")
    args = ap.parse_args()

    in_path = Path(args.input).expanduser().resolve()
    out_path = Path(args.output).expanduser().resolve()
    if args.width <= 0 or args.height <= 0:
        raise ValueError("width/height must be positive")
    if args.r_warp <= 0:
        raise ValueError("r-warp must be > 0")

    if in_path.suffix.lower() == ".npz":
        src = _load_npz(in_path)
    elif in_path.suffix.lower() == ".csv":
        src = _load_csv(in_path)
    else:
        raise ValueError("input must be .npz or .csv")

    r_norm = _pick(src, "emit_r_norm", "r_norm")
    phi = _pick(src, "emit_phi", "phi")
    temp_raw = _pick_optional(src, 1.0, "temperature", "T")
    vr_ratio = _pick_optional(src, 0.0, "vr_ratio", "v_r_ratio")
    vphi_scale = _pick_optional(src, 1.0, "vphi_scale", "v_phi_scale")

    if args.density_source == "density":
        density = _pick_optional(src, np.nan, "density", "rho")
        if np.isnan(density).all():
            density = _pick_optional(src, 0.0, "noise", "density")
    elif args.density_source == "noise":
        density = _pick_optional(src, 0.0, "noise", "density")
    else:
        density = np.ones_like(r_norm)

    # Convert raw temperature into radial-law relative scale so atlas stays near O(1).
    r_safe = np.maximum(r_norm, 1.0001)
    c_ref = np.median(temp_raw * np.power(r_safe, 0.75))
    t_ref = c_ref * np.power(r_safe, -0.75)
    temp_scale = np.divide(temp_raw, np.maximum(t_ref, 1e-12))

    atlas = _build_atlas(
        r_norm=r_norm,
        phi=phi,
        temp=temp_scale,
        density=density,
        vr_ratio=vr_ratio,
        vphi_scale=vphi_scale,
        width=args.width,
        height=args.height,
        r_min=args.r_min,
        r_max=args.r_max,
        r_warp=args.r_warp,
    )

    atlas.tofile(out_path)
    meta = {
        "width": args.width,
        "height": args.height,
        "format": "float4",
        "channels": ["temp_scale", "density", "vr_ratio", "vphi_scale"],
        "source": str(in_path),
        "rNormMin": args.r_min,
        "rNormMax": args.r_max,
        "rNormWarp": args.r_warp,
    }
    with (Path(str(out_path) + ".json")).open("w", encoding="utf-8") as f:
        json.dump(meta, f, ensure_ascii=True, indent=2, sort_keys=True)

    print(f"saved atlas: {out_path} ({args.width}x{args.height})")
    print(f"saved meta: {out_path}.json")


if __name__ == "__main__":
    main()
