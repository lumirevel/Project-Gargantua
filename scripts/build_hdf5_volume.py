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


def _resample_periodic_phi(field: np.ndarray, out_nphi: int) -> np.ndarray:
    src_nphi = field.shape[1]
    if src_nphi == out_nphi:
        return field.copy()
    xp = np.arange(src_nphi, dtype=np.float64)
    x_out = np.linspace(0.0, float(src_nphi), out_nphi, endpoint=False, dtype=np.float64)
    x0 = np.floor(x_out).astype(np.int64) % src_nphi
    x1 = (x0 + 1) % src_nphi
    t = x_out - np.floor(x_out)
    return field[:, x0] * (1.0 - t)[None, :] + field[:, x1] * t[None, :]


def _resample_rphi(field: np.ndarray, r_src: np.ndarray, r_dst: np.ndarray, out_nphi: int) -> np.ndarray:
    phi_resampled = _resample_periodic_phi(field, out_nphi)
    if np.array_equal(r_src, r_dst):
        return phi_resampled

    out = np.empty((r_dst.size, out_nphi), dtype=np.float64)
    for j in range(out_nphi):
        out[:, j] = np.interp(r_dst, r_src, phi_resampled[:, j], left=phi_resampled[0, j], right=phi_resampled[-1, j])
    return out


def main() -> None:
    ap = argparse.ArgumentParser(description="Build 3D disk volume (float4) from an offline HDF5 snapshot.")
    ap.add_argument("--input", required=True, help="input HDF5 snapshot path")
    ap.add_argument("--output", required=True, help="output volume .bin path")
    ap.add_argument("--nr", type=int, default=128, help="output radial bins")
    ap.add_argument("--nphi", type=int, default=256, help="output azimuth bins")
    ap.add_argument("--nz", type=int, default=72, help="output vertical bins")
    ap.add_argument("--r-min", type=float, default=-1.0, help="minimum r/rs in output (default: auto from input)")
    ap.add_argument("--r-max", type=float, default=-1.0, help="maximum r/rs in output (default: auto from input)")
    ap.add_argument("--z-max", type=float, default=0.08, help="maximum |z|/rs in output volume")
    ap.add_argument("--r-to-rs", type=float, default=1.0, help="multiplier to convert input radius to r/rs")
    ap.add_argument("--kepler-gm", type=float, default=1.0, help="GM value used for velocity normalization")
    ap.add_argument("--theta-index", type=int, default=-1, help="theta index for 3D fields (-1=mid plane)")
    ap.add_argument("--theta-average", action="store_true", help="average extra axes instead of theta slicing")
    ap.add_argument("--list-datasets", action="store_true", help="list dataset keys and exit")
    ap.add_argument("--r-key", default="", help="radius dataset key/path")
    ap.add_argument("--phi-key", default="", help="azimuth dataset key/path")
    ap.add_argument("--rho-key", default="", help="density dataset key/path")
    ap.add_argument("--temp-key", default="", help="temperature dataset key/path")
    ap.add_argument("--vr-key", default="", help="radial velocity dataset key/path")
    ap.add_argument("--vphi-key", default="", help="azimuth velocity dataset key/path")
    ap.add_argument("--temp-is-scale", action="store_true", help="treat temperature field as already normalized scale")
    ap.add_argument("--vr-is-ratio", action="store_true", help="treat vr field as already v_r / v_k")
    ap.add_argument("--vphi-is-scale", action="store_true", help="treat vphi field as already v_phi / v_k")
    ap.add_argument("--density-log", action="store_true", help="log10-normalize density before percentile scaling")
    ap.add_argument("--density-p-lo", type=float, default=5.0, help="lower percentile for density normalization")
    ap.add_argument("--density-p-hi", type=float, default=95.0, help="upper percentile for density normalization")
    ap.add_argument("--vertical-density-exp", type=float, default=2.6, help="vertical density exponent")
    ap.add_argument("--vertical-density-scale", type=float, default=0.18, help="vertical density profile scale in [0,1]")
    ap.add_argument("--vertical-temp-drop", type=float, default=0.54, help="temperature reduction at |z|=zMax")
    ap.add_argument("--vertical-vphi-drop", type=float, default=0.30, help="orbital velocity reduction at |z|=zMax")
    ap.add_argument("--vertical-vr-scale", type=float, default=0.34, help="radial drift attenuation scale in [0,1]")
    ap.add_argument(
        "--synthetic-clump",
        type=float,
        default=0.0,
        help="optional non-physical clump injection strength [0..1] (default: 0, disabled for scientific mode)",
    )
    args = ap.parse_args()

    if h5py is None:
        raise RuntimeError("h5py is required. install with: python3 -m pip install h5py")
    if args.nr < 2 or args.nphi < 4 or args.nz < 2:
        raise ValueError("nr/nphi/nz are too small")
    if args.r_to_rs <= 0:
        raise ValueError("r-to-rs must be > 0")
    if args.kepler_gm <= 0:
        raise ValueError("kepler-gm must be > 0")
    if args.z_max <= 0:
        raise ValueError("z-max must be > 0")
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
        nr_src = int(r.size)
        nphi_src = int(phi.size)
        if nr_src < 2 or nphi_src < 2:
            raise ValueError(f"invalid coordinate sizes: r={nr_src}, phi={nphi_src}")

        rho_2d = _extract_rphi_plane(np.asarray(ds_map[rho_key]), nr_src, nphi_src, args.theta_index, args.theta_average, "rho")
        temp_2d = _extract_rphi_plane(np.asarray(ds_map[temp_key]), nr_src, nphi_src, args.theta_index, args.theta_average, "temp")
        vr_2d = _extract_rphi_plane(np.asarray(ds_map[vr_key]), nr_src, nphi_src, args.theta_index, args.theta_average, "vr")
        vphi_2d = _extract_rphi_plane(np.asarray(ds_map[vphi_key]), nr_src, nphi_src, args.theta_index, args.theta_average, "vphi")

    r_norm_src = np.asarray(r, dtype=np.float64) * args.r_to_rs
    src_r_min = float(np.nanmin(r_norm_src))
    src_r_max = float(np.nanmax(r_norm_src))
    r_min = src_r_min if args.r_min <= 0.0 else float(args.r_min)
    r_max = src_r_max if args.r_max <= 0.0 else float(args.r_max)
    if not (r_max > r_min):
        raise ValueError(f"invalid radial range: r_min={r_min}, r_max={r_max}")

    r_dst = np.linspace(r_min, r_max, args.nr, dtype=np.float64)
    rr_src, _ = np.meshgrid(r_norm_src, np.asarray(phi, dtype=np.float64), indexing="ij")
    v_k_src = np.sqrt(args.kepler_gm / np.maximum(rr_src, 1e-12))

    temp_scale_src = _normalize_temperature(temp_2d, rr_src, args.temp_is_scale)
    density_src = _normalize_density(rho_2d, args.density_log, args.density_p_lo, args.density_p_hi)
    vr_ratio_src = _velocity_to_ratio(vr_2d, v_k_src, args.vr_is_ratio)
    vphi_scale_src = _velocity_to_ratio(vphi_2d, v_k_src, args.vphi_is_scale)

    temp_scale = _resample_rphi(temp_scale_src, r_norm_src, r_dst, args.nphi)
    density = _resample_rphi(density_src, r_norm_src, r_dst, args.nphi)
    vr_ratio = _resample_rphi(vr_ratio_src, r_norm_src, r_dst, args.nphi)
    vphi_scale = _resample_rphi(vphi_scale_src, r_norm_src, r_dst, args.nphi)

    clump_strength = float(np.clip(args.synthetic_clump, 0.0, 1.0))
    if clump_strength > 0.0:
        # Optional artistic clump injection. Keep disabled by default in scientific mode.
        phi_dst = np.linspace(0.0, 2.0 * np.pi, args.nphi, endpoint=False, dtype=np.float64)
        rr_dst, pp_dst = np.meshgrid(r_dst, phi_dst, indexing="ij")
        shear = pp_dst + 1.85 * np.log(np.maximum(rr_dst, 1.0))
        band1 = 0.5 + 0.5 * np.sin(21.0 * shear + 2.7 * np.sin(3.0 * pp_dst))
        band2 = 0.5 + 0.5 * np.sin(9.0 * pp_dst - 6.0 * np.sqrt(np.maximum(rr_dst, 1.0)))
        clump = np.clip(0.58 * band1 + 0.42 * band2, 0.0, 1.0)
        threshold = 0.34 + 0.18 * (1.0 - density)
        sparse = np.clip((clump - threshold) / np.maximum(1.0 - threshold, 1e-6), 0.0, 1.0)

        d_mix = (0.32 + 0.68 * sparse)
        t_mix = (0.88 + 0.22 * np.power(sparse, 0.95))
        vr_mix = (0.82 + 0.26 * sparse)
        vp_mix = (0.94 + 0.10 * sparse)
        density *= (1.0 - clump_strength) + clump_strength * d_mix
        temp_scale *= (1.0 - clump_strength) + clump_strength * t_mix
        vr_ratio *= (1.0 - clump_strength) + clump_strength * vr_mix
        vphi_scale *= (1.0 - clump_strength) + clump_strength * vp_mix
        if clump_strength > 0.5:
            gamma = 1.0 - 0.22 * (clump_strength - 0.5) / 0.5
            density = np.clip(np.power(np.clip(density, 0.0, 1.0), gamma), 0.0, 1.0)

    z = np.linspace(-args.z_max, args.z_max, args.nz, dtype=np.float64)
    z_abs01 = np.clip(np.abs(z) / max(args.z_max, 1e-12), 0.0, 1.0)
    dens_scale = np.exp(-np.power(z_abs01 / max(args.vertical_density_scale, 1e-3), max(args.vertical_density_exp, 0.4)))
    temp_scale_z = 1.0 - np.clip(args.vertical_temp_drop, 0.0, 0.95) * np.power(z_abs01, 1.2)
    vphi_scale_z = 1.0 - np.clip(args.vertical_vphi_drop, 0.0, 0.95) * np.power(z_abs01, 1.4)
    vr_scale_z = np.exp(-np.power(z_abs01 / max(args.vertical_vr_scale, 1e-3), 1.4))

    dens_scale = np.clip(dens_scale, 0.0, 1.0)
    temp_scale_z = np.clip(temp_scale_z, 0.1, 2.5)
    vphi_scale_z = np.clip(vphi_scale_z, 0.1, 2.5)
    vr_scale_z = np.clip(vr_scale_z, 0.0, 1.0)

    vol = np.zeros((args.nz, args.nphi, args.nr, 4), dtype=np.float32)
    for k in range(args.nz):
        vol[k, :, :, 0] = (temp_scale * temp_scale_z[k]).T.astype(np.float32)
        vol[k, :, :, 1] = (density * dens_scale[k]).T.astype(np.float32)
        vol[k, :, :, 2] = (vr_ratio * vr_scale_z[k]).T.astype(np.float32)
        vol[k, :, :, 3] = (vphi_scale * vphi_scale_z[k]).T.astype(np.float32)

    vol[..., 0] = np.clip(vol[..., 0], 0.02, 40.0)
    vol[..., 1] = np.clip(vol[..., 1], 0.0, 1.0)
    vol[..., 2] = np.clip(vol[..., 2], -1.0, 1.0)
    vol[..., 3] = np.clip(vol[..., 3], 0.0, 4.0)

    out_path.parent.mkdir(parents=True, exist_ok=True)
    vol.tofile(out_path)

    meta = {
        "r": args.nr,
        "phi": args.nphi,
        "z": args.nz,
        "format": "float4",
        "channels": ["temp_scale", "density", "vr_ratio", "vphi_scale"],
        "source": str(in_path),
        "rNormMin": r_min,
        "rNormMax": r_max,
        "zNormMax": float(args.z_max),
        "rToRs": float(args.r_to_rs),
        "keplerGm": float(args.kepler_gm),
        "thetaIndex": int(args.theta_index),
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
            "densityPLo": float(args.density_p_lo),
            "densityPHi": float(args.density_p_hi),
        },
        "syntheticClump": float(clump_strength),
        "verticalProfile": {
            "densityExp": float(args.vertical_density_exp),
            "densityScale": float(args.vertical_density_scale),
            "tempDrop": float(args.vertical_temp_drop),
            "vphiDrop": float(args.vertical_vphi_drop),
            "vrScale": float(args.vertical_vr_scale),
        },
    }
    meta_path = Path(str(out_path) + ".json")
    with meta_path.open("w", encoding="utf-8") as f:
        json.dump(meta, f, ensure_ascii=True, indent=2, sort_keys=True)

    print(f"saved volume: {out_path} ({args.nr}x{args.nphi}x{args.nz})")
    print(f"rNorm=[{r_min:.4f}, {r_max:.4f}], zNormMax={args.z_max:.4f}")


if __name__ == "__main__":
    main()
