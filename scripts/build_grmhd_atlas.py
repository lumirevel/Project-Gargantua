#!/usr/bin/env python3
import argparse
import json
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Tuple

import numpy as np

try:
    import h5py  # type: ignore
except Exception:  # pragma: no cover - runtime dependency check
    h5py = None


def _collect_datasets(h5: "h5py.File") -> Dict[str, "h5py.Dataset"]:
    out: Dict[str, "h5py.Dataset"] = {}

    def visit(name: str, obj: object) -> None:
        if isinstance(obj, h5py.Dataset):
            out[name] = obj

    h5.visititems(visit)
    return out


def _matches(ds_map: Dict[str, "h5py.Dataset"], key: str) -> List[str]:
    if key in ds_map:
        return [key]
    suffix = "/" + key
    return [name for name in ds_map.keys() if name.endswith(suffix) or name == key]


def _resolve_key(
    ds_map: Dict[str, "h5py.Dataset"],
    explicit: str,
    candidates: Iterable[str],
    label: str,
) -> str:
    if explicit:
        m = _matches(ds_map, explicit)
        if len(m) == 1:
            return m[0]
        if len(m) > 1:
            raise ValueError(f"ambiguous {label} key '{explicit}': matches={m}")
        raise KeyError(f"{label} key '{explicit}' not found")

    for cand in candidates:
        m = _matches(ds_map, cand)
        if len(m) == 1:
            return m[0]
        if len(m) > 1:
            # Pick the shortest path when auto-detection is ambiguous.
            m_sorted = sorted(m, key=len)
            return m_sorted[0]

    tried = ", ".join(candidates)
    raise KeyError(f"failed to auto-detect {label}; tried: {tried}")


def _coord_1d(arr: np.ndarray, label: str) -> np.ndarray:
    a = np.asarray(arr, dtype=np.float64).squeeze()
    if a.ndim == 1:
        return a
    if a.ndim == 2:
        # Typical meshgrid case: r is almost constant along phi, phi along r.
        std0 = float(np.nanmean(np.nanstd(a, axis=0)))
        std1 = float(np.nanmean(np.nanstd(a, axis=1)))
        if std0 <= std1:
            return np.nanmean(a, axis=0)
        return np.nanmean(a, axis=1)
    raise ValueError(f"{label} coordinate must be 1D or 2D; got shape={a.shape}")


def _extract_rphi_plane(
    arr: np.ndarray,
    nr: int,
    nphi: int,
    theta_index: int,
    theta_average: bool,
    name: str,
) -> np.ndarray:
    x = np.asarray(arr, dtype=np.float64).squeeze()
    if x.ndim == 1 and x.size == nr * nphi:
        x = x.reshape(nr, nphi)
    if x.ndim < 2:
        raise ValueError(f"{name} must be >=2D or flattened nr*nphi; got shape={x.shape}")

    r_axes = [i for i, s in enumerate(x.shape) if s == nr]
    p_axes = [i for i, s in enumerate(x.shape) if s == nphi]
    if not r_axes or not p_axes:
        raise ValueError(
            f"{name}: cannot find r/phi axes for nr={nr}, nphi={nphi}, shape={x.shape}. "
            "Use preprocessed arrays or matching coordinate lengths."
        )

    pair: Optional[Tuple[int, int]] = None
    for ra in r_axes:
        for pa in p_axes:
            if ra != pa:
                pair = (ra, pa)
                break
        if pair is not None:
            break
    if pair is None:
        raise ValueError(f"{name}: ambiguous axis mapping for shape={x.shape}")

    r_axis, p_axis = pair
    x = np.moveaxis(x, [r_axis, p_axis], [0, 1])

    if x.ndim > 2:
        if theta_average:
            x = np.nanmean(x, axis=tuple(range(2, x.ndim)))
        else:
            slicer: List[object] = [slice(None), slice(None)]
            for ax in range(2, x.ndim):
                n = x.shape[ax]
                idx = theta_index if theta_index >= 0 else (n // 2)
                idx = max(0, min(n - 1, idx))
                slicer.append(idx)
            x = x[tuple(slicer)]

    if x.shape == (nr, nphi):
        return x
    if x.shape == (nphi, nr):
        return x.T
    raise ValueError(f"{name}: expected {(nr, nphi)} after reduction; got {x.shape}")


def _aggregate_mean(values: np.ndarray, flat_idx: np.ndarray, n_cells: int) -> Tuple[np.ndarray, np.ndarray]:
    sums = np.bincount(flat_idx, weights=values, minlength=n_cells).astype(np.float64)
    counts = np.bincount(flat_idx, minlength=n_cells).astype(np.float64)
    out = np.zeros(n_cells, dtype=np.float64)
    nz = counts > 0
    out[nz] = sums[nz] / counts[nz]
    return out, counts


def _fill_holes(field: np.ndarray, counts: np.ndarray) -> np.ndarray:
    out = field.copy()
    h, _ = out.shape
    global_med = float(np.median(out[counts > 0])) if np.any(counts > 0) else 0.0
    for y in range(h):
        row_mask = counts[y] > 0
        row_med = float(np.median(out[y, row_mask])) if np.any(row_mask) else global_med
        out[y, ~row_mask] = row_med
    return out


def _build_atlas(
    r_norm: np.ndarray,
    phi: np.ndarray,
    temp_scale: np.ndarray,
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

    t_flat, cnt = _aggregate_mean(temp_scale, flat, n_cells)
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


def _normalize_density(rho: np.ndarray, use_log: bool, p_lo: float, p_hi: float) -> np.ndarray:
    x = np.asarray(rho, dtype=np.float64)
    if use_log:
        x = np.log10(np.maximum(x, 1e-30))
    lo = float(np.nanpercentile(x, p_lo))
    hi = float(np.nanpercentile(x, p_hi))
    if not np.isfinite(lo) or not np.isfinite(hi) or hi <= lo:
        return np.zeros_like(x, dtype=np.float64)
    return np.clip((x - lo) / (hi - lo), 0.0, 1.0)


def _normalize_temperature(temp: np.ndarray, r_norm_2d: np.ndarray, already_scale: bool) -> np.ndarray:
    t = np.asarray(temp, dtype=np.float64)
    if already_scale:
        return t
    r_safe = np.maximum(r_norm_2d, 1.0001)
    c_ref = float(np.nanmedian(t * np.power(r_safe, 0.75)))
    t_ref = c_ref * np.power(r_safe, -0.75)
    return np.divide(t, np.maximum(t_ref, 1e-12))


def _velocity_to_ratio(v: np.ndarray, v_k: np.ndarray, already_ratio: bool) -> np.ndarray:
    if already_ratio:
        return np.asarray(v, dtype=np.float64)
    return np.asarray(v, dtype=np.float64) / np.maximum(v_k, 1e-12)


def main() -> None:
    ap = argparse.ArgumentParser(description="Build disk_atlas.bin from an offline GRMHD HDF5 snapshot")
    ap.add_argument("--input", required=True, help="input HDF5 snapshot path")
    ap.add_argument("--output", required=True, help="output atlas .bin path")
    ap.add_argument("--width", type=int, default=1024, help="atlas width (phi bins)")
    ap.add_argument("--height", type=int, default=512, help="atlas height (radial bins)")
    ap.add_argument("--r-min", type=float, default=1.0, help="minimum r/rs mapped to atlas row 0")
    ap.add_argument("--r-max", type=float, default=9.0, help="maximum r/rs mapped to atlas last row")
    ap.add_argument("--r-warp", type=float, default=0.65, help="radial mapping exponent (<1 increases inner resolution)")
    ap.add_argument("--r-to-rs", type=float, default=1.0, help="multiplier to convert input radius to r/rs")
    ap.add_argument("--kepler-gm", type=float, default=1.0, help="GM value in the same unit system as radius for velocity normalization")
    ap.add_argument("--theta-index", type=int, default=-1, help="theta index to sample for 3D fields (-1=mid plane)")
    ap.add_argument("--theta-average", action="store_true", help="average over extra axes instead of theta slicing")
    ap.add_argument("--list-datasets", action="store_true", help="list available HDF5 datasets and exit")
    ap.add_argument("--r-key", default="", help="radius dataset key/path (auto if omitted)")
    ap.add_argument("--phi-key", default="", help="azimuth dataset key/path (auto if omitted)")
    ap.add_argument("--rho-key", default="", help="density dataset key/path (auto if omitted)")
    ap.add_argument("--temp-key", default="", help="temperature dataset key/path (auto if omitted)")
    ap.add_argument("--vr-key", default="", help="radial velocity dataset key/path (auto if omitted)")
    ap.add_argument("--vphi-key", default="", help="azimuth velocity dataset key/path (auto if omitted)")
    ap.add_argument("--temp-is-scale", action="store_true", help="treat temperature field as already normalized scale")
    ap.add_argument("--vr-is-ratio", action="store_true", help="treat vr field as already v_r / v_k")
    ap.add_argument("--vphi-is-scale", action="store_true", help="treat vphi field as already v_phi / v_k")
    ap.add_argument("--density-log", action="store_true", help="log10-normalize density before percentile scaling")
    ap.add_argument("--density-p-lo", type=float, default=5.0, help="lower percentile for density normalization")
    ap.add_argument("--density-p-hi", type=float, default=95.0, help="upper percentile for density normalization")
    args = ap.parse_args()

    if h5py is None:
        raise RuntimeError("h5py is required. install with: python3 -m pip install h5py")

    if args.width <= 0 or args.height <= 0:
        raise ValueError("width/height must be positive")
    if not (args.r_max > args.r_min):
        raise ValueError("r-max must be greater than r-min")
    if args.r_warp <= 0:
        raise ValueError("r-warp must be > 0")
    if args.r_to_rs <= 0:
        raise ValueError("r-to-rs must be > 0")
    if args.kepler_gm <= 0:
        raise ValueError("kepler-gm must be > 0")
    if not (0.0 <= args.density_p_lo < args.density_p_hi <= 100.0):
        raise ValueError("density percentiles must satisfy 0 <= p_lo < p_hi <= 100")

    in_path = Path(args.input).expanduser().resolve()
    out_path = Path(args.output).expanduser().resolve()

    with h5py.File(in_path, "r") as h5:
        ds_map = _collect_datasets(h5)
        if not ds_map:
            raise ValueError(f"no datasets found in {in_path}")

        if args.list_datasets:
            for name in sorted(ds_map.keys()):
                ds = ds_map[name]
                print(f"{name}\tshape={tuple(ds.shape)}\tdtype={ds.dtype}")
            return

        r_key = _resolve_key(ds_map, args.r_key, ["r", "radius", "x1v", "x1", "X1", "grid/r"], "radius")
        phi_key = _resolve_key(ds_map, args.phi_key, ["phi", "x3v", "x3", "X3", "grid/phi"], "phi")
        rho_key = _resolve_key(ds_map, args.rho_key, ["rho", "density", "dens", "RHO", "Density"], "density")
        temp_key = _resolve_key(
            ds_map,
            args.temp_key,
            ["temp_scale", "temperature", "temp", "Theta", "theta_e", "Te", "u", "prs", "press", "pressure"],
            "temperature",
        )
        vr_key = _resolve_key(ds_map, args.vr_key, ["vr_ratio", "vr", "v_r", "vx1", "u1", "v1", "vel1"], "radial velocity")
        vphi_key = _resolve_key(ds_map, args.vphi_key, ["vphi_scale", "vphi", "v_phi", "vx3", "u3", "v3", "vel3"], "azimuth velocity")

        r = _coord_1d(np.asarray(ds_map[r_key]), "r")
        phi = _coord_1d(np.asarray(ds_map[phi_key]), "phi")
        if r.size < 2 or phi.size < 2:
            raise ValueError(f"invalid coordinate sizes: r={r.size}, phi={phi.size}")

        nr = int(r.size)
        nphi = int(phi.size)
        r_norm_1d = np.asarray(r, dtype=np.float64) * args.r_to_rs
        phi_1d = np.mod(np.asarray(phi, dtype=np.float64), 2.0 * np.pi)

        rho_2d = _extract_rphi_plane(np.asarray(ds_map[rho_key]), nr, nphi, args.theta_index, args.theta_average, "rho")
        temp_2d = _extract_rphi_plane(np.asarray(ds_map[temp_key]), nr, nphi, args.theta_index, args.theta_average, "temp")
        vr_2d = _extract_rphi_plane(np.asarray(ds_map[vr_key]), nr, nphi, args.theta_index, args.theta_average, "vr")
        vphi_2d = _extract_rphi_plane(np.asarray(ds_map[vphi_key]), nr, nphi, args.theta_index, args.theta_average, "vphi")

    rr, pp = np.meshgrid(r_norm_1d, phi_1d, indexing="ij")
    v_k = np.sqrt(args.kepler_gm / np.maximum(rr, 1e-12))

    temp_scale_2d = _normalize_temperature(temp_2d, rr, args.temp_is_scale)
    density_2d = _normalize_density(rho_2d, args.density_log, args.density_p_lo, args.density_p_hi)
    vr_ratio_2d = _velocity_to_ratio(vr_2d, v_k, args.vr_is_ratio)
    vphi_scale_2d = _velocity_to_ratio(vphi_2d, v_k, args.vphi_is_scale)

    atlas = _build_atlas(
        r_norm=rr.ravel(),
        phi=pp.ravel(),
        temp_scale=temp_scale_2d.ravel(),
        density=density_2d.ravel(),
        vr_ratio=vr_ratio_2d.ravel(),
        vphi_scale=vphi_scale_2d.ravel(),
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
        "rToRs": args.r_to_rs,
        "keplerGm": args.kepler_gm,
        "thetaIndex": args.theta_index,
        "thetaAverage": bool(args.theta_average),
        "keys": {
            "r": r_key,
            "phi": phi_key,
            "rho": rho_key,
            "temp": temp_key,
            "vr": vr_key,
            "vphi": vphi_key,
        },
        "normalization": {
            "tempIsScale": bool(args.temp_is_scale),
            "vrIsRatio": bool(args.vr_is_ratio),
            "vphiIsScale": bool(args.vphi_is_scale),
            "densityLog": bool(args.density_log),
            "densityPLo": args.density_p_lo,
            "densityPHi": args.density_p_hi,
        },
    }
    meta_path = Path(str(out_path) + ".json")
    with meta_path.open("w", encoding="utf-8") as f:
        json.dump(meta, f, ensure_ascii=True, indent=2, sort_keys=True)

    print(f"saved atlas: {out_path} ({args.width}x{args.height})")
    print(f"saved meta: {meta_path}")


if __name__ == "__main__":
    main()
