#!/usr/bin/env python3
import argparse
import json
import math
from datetime import datetime
from pathlib import Path
from typing import Optional

import numpy as np
try:
    from PIL import Image
except Exception:
    Image = None

LUMA = np.array([0.2126, 0.7152, 0.0722], dtype=np.float64)


def read_ppm(path: Path) -> np.ndarray:
    with path.open("rb") as f:
        magic = f.readline().strip()
        if magic != b"P6":
            raise ValueError(f"expected P6 PPM, got {magic!r}")
        line = f.readline()
        while line.startswith(b"#"):
            line = f.readline()
        width, height = map(int, line.strip().split())
        maxv = int(f.readline().strip())
        if maxv != 255:
            raise ValueError(f"expected max value 255, got {maxv}")
        raw = f.read()
    expected = width * height * 3
    if len(raw) != expected:
        raise ValueError(f"PPM payload size mismatch: got {len(raw)}, expected {expected}")
    return np.frombuffer(raw, dtype=np.uint8).reshape(height, width, 3)


def load_image(path: Path) -> np.ndarray:
    if Image is not None:
        with Image.open(path) as im:
            return np.asarray(im.convert("RGB"), dtype=np.uint8)
    if path.suffix.lower() == ".ppm":
        return read_ppm(path)
    raise RuntimeError("Pillow is not available; non-PPM formats require Pillow.")


def compute_global_ssim(x: np.ndarray, y: np.ndarray) -> float:
    ux = float(x.mean())
    uy = float(y.mean())
    vx = float(np.mean((x - ux) ** 2))
    vy = float(np.mean((y - uy) ** 2))
    cxy = float(np.mean((x - ux) * (y - uy)))
    c1 = (0.01 * 255.0) ** 2
    c2 = (0.03 * 255.0) ** 2
    denom = (ux * ux + uy * uy + c1) * (vx + vy + c2)
    if denom <= 1e-12:
        return 1.0
    num = (2.0 * ux * uy + c1) * (2.0 * cxy + c2)
    return float(num / denom)


def masked_pixels(img: np.ndarray, mask: np.ndarray) -> np.ndarray:
    # Flattened RGB pixels selected by mask.
    return img[mask]


def main() -> None:
    p = argparse.ArgumentParser(description="Compare candidate image against reference (L2/RMSE/PSNR/SSIM).")
    p.add_argument("--candidate", required=True, help="candidate image path (png/ppm/...)")
    p.add_argument("--reference", required=True, help="reference image path (png/ppm/...)")
    p.add_argument("--output-json", default="", help="optional JSON report path")
    p.add_argument(
        "--mask-luma-threshold",
        type=float,
        default=0.0,
        help="optional normalized luma threshold [0..1] on reference; compare only masked pixels",
    )
    p.add_argument("--max-rmse", type=float, default=-1.0, help="optional pass/fail threshold")
    p.add_argument("--max-rel-l2", type=float, default=-1.0, help="optional pass/fail threshold")
    args = p.parse_args()

    cand_src = Path(args.candidate).expanduser().resolve()
    ref_src = Path(args.reference).expanduser().resolve()
    if not cand_src.exists():
        raise FileNotFoundError(f"candidate not found: {cand_src}")
    if not ref_src.exists():
        raise FileNotFoundError(f"reference not found: {ref_src}")

    cand = load_image(cand_src).astype(np.float64)
    ref = load_image(ref_src).astype(np.float64)

    if cand.shape != ref.shape:
        raise ValueError(f"shape mismatch: candidate={cand.shape}, reference={ref.shape}")

    thr = float(max(0.0, min(1.0, args.mask_luma_threshold)))
    if thr > 0.0:
        ref_luma = ref @ LUMA
        mask = (ref_luma / 255.0) >= thr
        if not np.any(mask):
            raise ValueError("mask is empty; lower --mask-luma-threshold")
        cand_sel = masked_pixels(cand, mask)
        ref_sel = masked_pixels(ref, mask)
    else:
        mask = None
        cand_sel = cand.reshape(-1, 3)
        ref_sel = ref.reshape(-1, 3)

    diff = cand_sel - ref_sel
    mse = float(np.mean(diff * diff))
    rmse = float(math.sqrt(mse))
    mae = float(np.mean(np.abs(diff)))
    max_abs = float(np.max(np.abs(diff)))
    ref_energy = float(np.sum(ref_sel * ref_sel))
    l2 = float(math.sqrt(np.sum(diff * diff)))
    rel_l2 = float(l2 / math.sqrt(max(ref_energy, 1e-12)))
    psnr = float("inf") if mse <= 1e-12 else float(20.0 * math.log10(255.0 / rmse))

    if mask is not None:
        cand_luma = cand[mask] @ LUMA
        ref_luma = ref[mask] @ LUMA
    else:
        cand_luma = cand.reshape(-1, 3) @ LUMA
        ref_luma = ref.reshape(-1, 3) @ LUMA
    ssim_global = compute_global_ssim(cand_luma, ref_luma)

    result = {
        "created": datetime.now().isoformat(timespec="seconds"),
        "candidate": str(cand_src),
        "reference": str(ref_src),
        "width": int(cand.shape[1]),
        "height": int(cand.shape[0]),
        "pixels_compared": int(cand_sel.shape[0]),
        "mask_luma_threshold": thr,
        "mse": mse,
        "rmse": rmse,
        "mae": mae,
        "max_abs": max_abs,
        "l2": l2,
        "rel_l2": rel_l2,
        "psnr_db": None if not math.isfinite(psnr) else psnr,
        "ssim_global_luma": ssim_global,
    }

    print(
        "VERIFY_IMAGE "
        f"pixels={result['pixels_compared']} "
        f"rmse={rmse:.6f} rel_l2={rel_l2:.6f} "
        f"psnr={'inf' if not math.isfinite(psnr) else f'{psnr:.4f}'} "
        f"ssim={ssim_global:.6f}"
    )

    if args.output_json:
        out = Path(args.output_json).expanduser().resolve()
        out.parent.mkdir(parents=True, exist_ok=True)
        with out.open("w", encoding="utf-8") as f:
            json.dump(result, f, ensure_ascii=False, indent=2, sort_keys=True)
        print(f"VERIFY_REPORT {out}")

    fail_reason = []
    if args.max_rmse >= 0.0 and rmse > args.max_rmse:
        fail_reason.append(f"rmse={rmse:.6f} > max_rmse={args.max_rmse:.6f}")
    if args.max_rel_l2 >= 0.0 and rel_l2 > args.max_rel_l2:
        fail_reason.append(f"rel_l2={rel_l2:.6f} > max_rel_l2={args.max_rel_l2:.6f}")
    if fail_reason:
        print("VERIFY_FAIL " + "; ".join(fail_reason))
        raise SystemExit(3)


if __name__ == "__main__":
    main()
