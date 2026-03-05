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
            return sorted(m, key=len)[0]

    tried = ", ".join(candidates)
    raise KeyError(f"failed to auto-detect {label}; tried: {tried}")


def _coord_1d(arr: np.ndarray, label: str) -> np.ndarray:
    a = np.asarray(arr, dtype=np.float64).squeeze()
    if a.ndim == 1:
        return a
    if a.ndim == 2:
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
        raise ValueError(f"{name}: cannot find r/phi axes for nr={nr}, nphi={nphi}, shape={x.shape}")

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


def _robust_sigma(x: np.ndarray) -> float:
    med = float(np.nanmedian(x))
    mad = float(np.nanmedian(np.abs(x - med)))
    return 1.4826 * mad


def _clip_finite(v: float, lo: float, hi: float, default: float) -> float:
    if not np.isfinite(v):
        return default
    return float(np.clip(v, lo, hi))


def main() -> None:
    ap = argparse.ArgumentParser(description="Extract flow profile from an offline GRMHD HDF5 snapshot.")
    ap.add_argument("--input", required=True, help="input HDF5 snapshot path")
    ap.add_argument("--output", required=True, help="output JSON flow profile path")
    ap.add_argument("--r-to-rs", type=float, default=1.0, help="multiplier to convert input radius to r/rs")
    ap.add_argument("--kepler-gm", type=float, default=1.0, help="GM in same unit as radius")
    ap.add_argument("--theta-index", type=int, default=-1, help="theta index for 3D fields (-1=mid)")
    ap.add_argument("--theta-average", action="store_true", help="average extra axes instead of theta slicing")
    ap.add_argument("--list-datasets", action="store_true", help="list dataset keys and exit")
    ap.add_argument("--r-key", default="", help="radius dataset key/path")
    ap.add_argument("--phi-key", default="", help="azimuth dataset key/path")
    ap.add_argument("--rho-key", default="", help="density dataset key/path")
    ap.add_argument("--vr-key", default="", help="radial velocity dataset key/path")
    ap.add_argument("--vphi-key", default="", help="azimuth velocity dataset key/path")
    args = ap.parse_args()

    if h5py is None:
        raise RuntimeError("h5py is required. install with: python3 -m pip install h5py")
    if args.r_to_rs <= 0:
        raise ValueError("r-to-rs must be > 0")
    if args.kepler_gm <= 0:
        raise ValueError("kepler-gm must be > 0")

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
        vr_key = _resolve_key(ds_map, args.vr_key, ["vr", "v_r", "vx1", "u1", "v1", "vel1"], "radial velocity")
        vphi_key = _resolve_key(ds_map, args.vphi_key, ["vphi", "v_phi", "vx3", "u3", "v3", "vel3"], "azimuth velocity")

        r = _coord_1d(np.asarray(ds_map[r_key]), "r")
        phi = _coord_1d(np.asarray(ds_map[phi_key]), "phi")
        nr = int(r.size)
        nphi = int(phi.size)
        if nr < 2 or nphi < 2:
            raise ValueError(f"invalid coordinate sizes: r={nr}, phi={nphi}")

        rho = _extract_rphi_plane(np.asarray(ds_map[rho_key]), nr, nphi, args.theta_index, args.theta_average, "rho")
        vr = _extract_rphi_plane(np.asarray(ds_map[vr_key]), nr, nphi, args.theta_index, args.theta_average, "vr")
        vphi = _extract_rphi_plane(np.asarray(ds_map[vphi_key]), nr, nphi, args.theta_index, args.theta_average, "vphi")

    r_norm = np.asarray(r, dtype=np.float64) * args.r_to_rs
    rr, _ = np.meshgrid(r_norm, np.asarray(phi, dtype=np.float64), indexing="ij")
    v_k = np.sqrt(args.kepler_gm / np.maximum(rr, 1e-12))

    vphi_ratio = np.abs(vphi) / np.maximum(v_k, 1e-12)
    vr_in_ratio = np.maximum(-vr, 0.0) / np.maximum(v_k, 1e-12)

    orbital_boost = float(np.nanmedian(vphi_ratio))
    radial_drift = float(np.nanpercentile(vr_in_ratio, 60.0))

    r_q_inner = float(np.nanpercentile(rr, 35.0))
    r_q_outer = float(np.nanpercentile(rr, 70.0))
    inner_mask = rr <= r_q_inner
    outer_mask = rr >= r_q_outer
    if not np.any(inner_mask):
        inner_mask = np.ones_like(rr, dtype=bool)
    if not np.any(outer_mask):
        outer_mask = np.ones_like(rr, dtype=bool)

    orbital_boost_inner = float(np.nanmedian(vphi_ratio[inner_mask]))
    orbital_boost_outer = float(np.nanmedian(vphi_ratio[outer_mask]))
    radial_drift_inner = float(np.nanpercentile(vr_in_ratio[inner_mask], 60.0))
    radial_drift_outer = float(np.nanpercentile(vr_in_ratio[outer_mask], 60.0))

    log_rho = np.log(np.maximum(rho, 1e-30))
    radial_trend = np.nanmean(log_rho, axis=1, keepdims=True)
    rho_residual = log_rho - radial_trend
    sigma = _robust_sigma(rho_residual)
    turbulence = 0.18 + 0.55 * sigma
    turbulence_inner = 0.18 + 0.55 * _robust_sigma(rho_residual[inner_mask])
    turbulence_outer = 0.18 + 0.55 * _robust_sigma(rho_residual[outer_mask])

    flow_step = 0.22 / (1.0 + 0.55 * sigma)
    flow_steps = int(round(8.0 + 6.0 * sigma))

    orbital_boost = _clip_finite(orbital_boost, 0.2, 2.5, 1.0)
    orbital_boost_inner = _clip_finite(orbital_boost_inner, 0.2, 2.5, orbital_boost)
    orbital_boost_outer = _clip_finite(orbital_boost_outer, 0.2, 2.5, orbital_boost)
    radial_drift = _clip_finite(radial_drift, 0.0, 0.35, 0.02)
    radial_drift_inner = _clip_finite(radial_drift_inner, 0.0, 0.35, radial_drift)
    radial_drift_outer = _clip_finite(radial_drift_outer, 0.0, 0.35, radial_drift)
    turbulence = _clip_finite(turbulence, 0.05, 0.95, 0.30)
    turbulence_inner = _clip_finite(turbulence_inner, 0.05, 0.95, turbulence)
    turbulence_outer = _clip_finite(turbulence_outer, 0.05, 0.95, turbulence)
    flow_step = _clip_finite(flow_step, 0.08, 0.25, 0.22)
    flow_steps = int(np.clip(flow_steps, 6, 16)) if np.isfinite(flow_steps) else 8

    profile = {
        "source": str(in_path),
        "keys": {
            "r": r_key,
            "phi": phi_key,
            "rho": rho_key,
            "vr": vr_key,
            "vphi": vphi_key,
        },
        "recommend": {
            "disk_orbital_boost": orbital_boost,
            "disk_radial_drift": radial_drift,
            "disk_turbulence": turbulence,
            "disk_orbital_boost_inner": orbital_boost_inner,
            "disk_orbital_boost_outer": orbital_boost_outer,
            "disk_radial_drift_inner": radial_drift_inner,
            "disk_radial_drift_outer": radial_drift_outer,
            "disk_turbulence_inner": turbulence_inner,
            "disk_turbulence_outer": turbulence_outer,
            "disk_flow_step": flow_step,
            "disk_flow_steps": flow_steps,
        },
        "diagnostics": {
            "vphi_ratio_p50": float(np.nanpercentile(vphi_ratio, 50.0)),
            "vphi_ratio_p90": float(np.nanpercentile(vphi_ratio, 90.0)),
            "vr_in_ratio_p50": float(np.nanpercentile(vr_in_ratio, 50.0)),
            "vr_in_ratio_p90": float(np.nanpercentile(vr_in_ratio, 90.0)),
            "rho_residual_sigma": float(sigma),
            "r_inner_split": r_q_inner,
            "r_outer_split": r_q_outer,
            "nr": nr,
            "nphi": nphi,
        },
    }

    out_path.parent.mkdir(parents=True, exist_ok=True)
    with out_path.open("w", encoding="utf-8") as f:
        json.dump(profile, f, ensure_ascii=True, indent=2, sort_keys=True)

    print(f"saved flow profile: {out_path}")
    print(
        "recommend "
        f"orbital={orbital_boost:.4f} radial={radial_drift:.4f} "
        f"turb={turbulence:.4f} step={flow_step:.4f} steps={flow_steps} "
        f"(inner/outer orbital={orbital_boost_inner:.4f}/{orbital_boost_outer:.4f}, "
        f"radial={radial_drift_inner:.4f}/{radial_drift_outer:.4f}, "
        f"turb={turbulence_inner:.4f}/{turbulence_outer:.4f})"
    )


if __name__ == "__main__":
    main()
