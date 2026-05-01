#!/usr/bin/env python3
import argparse
import json
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Tuple

import numpy as np

try:
    import h5py  # type: ignore
except Exception:  # pragma: no cover - runtime dependency check
    h5py = None


def _collect_datasets(h5: "h5py.File") -> Dict[str, object]:
    out: Dict[str, object] = {}

    def visit(name: str, obj: object) -> None:
        if isinstance(obj, h5py.Dataset):
            out[name] = obj

    h5.visititems(visit)
    return out


def _matches(ds_map: Dict[str, object], key: str) -> List[str]:
    if key in ds_map:
        return [key]
    suffix = "/" + key
    return [name for name in ds_map.keys() if name.endswith(suffix) or name == key]


def _resolve_key(
    ds_map: Dict[str, object],
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


def _resolve_optional_key(
    ds_map: Dict[str, object],
    explicit: str,
    candidates: Iterable[str],
) -> Optional[str]:
    if explicit:
        m = _matches(ds_map, explicit)
        if len(m) == 1:
            return m[0]
        if len(m) > 1:
            raise ValueError(f"ambiguous key '{explicit}': matches={m}")
        raise KeyError(f"key '{explicit}' not found")

    for cand in candidates:
        m = _matches(ds_map, cand)
        if len(m) == 1:
            return m[0]
        if len(m) > 1:
            return sorted(m, key=len)[0]
    return None


def _decode_scalar(value: object) -> object:
    arr = np.asarray(value)
    if arr.shape == ():
        item = arr.item()
        if isinstance(item, bytes):
            return item.decode("utf-8", errors="replace").strip("\x00")
        if isinstance(item, np.generic):
            return item.item()
        return item
    return value


def _h5_value(h5: "h5py.File", key: str, default: object = None) -> object:
    if key not in h5:
        return default
    return _decode_scalar(h5[key][()])


def _h5_float(h5: "h5py.File", key: str, default: float) -> float:
    value = _h5_value(h5, key, default)
    try:
        return float(value)
    except Exception:
        return float(default)


def _fmks_theta_from_native_x2(h5: "h5py.File", x1: np.ndarray, x2: np.ndarray) -> np.ndarray:
    """Approximate FMKS native x2 -> Kerr-Schild theta for primitive dumps."""
    hslope = _h5_float(h5, "header/geom/fmks/hslope", _h5_float(h5, "header/hslope", 0.3))
    mks_smooth = _h5_float(h5, "header/geom/fmks/mks_smooth", _h5_float(h5, "header/mks_smooth", 0.5))
    poly_alpha = _h5_float(h5, "header/geom/fmks/poly_alpha", _h5_float(h5, "header/poly_alpha", 14.0))
    poly_xt = _h5_float(h5, "header/geom/fmks/poly_xt", _h5_float(h5, "header/poly_xt", 0.82))
    startx1 = _h5_float(h5, "header/geom/startx1", _h5_float(h5, "header/startx1", float(np.min(x1))))
    poly_norm = 0.5 * np.pi / (1.0 + (1.0 / (poly_alpha + 1.0)) / np.power(poly_xt, poly_alpha))
    th_g = np.pi * x2 + ((1.0 - hslope) * 0.5) * np.sin(2.0 * np.pi * x2)
    y = 2.0 * x2 - 1.0
    th_j = poly_norm * y * (1.0 + np.power(y / poly_xt, poly_alpha) / (poly_alpha + 1.0)) + 0.5 * np.pi
    theta = th_g + np.exp(mks_smooth * (startx1 - x1)) * (th_j - th_g)
    return np.clip(theta, 1.0e-6, np.pi - 1.0e-6)


def _inject_primitive_dump(h5: "h5py.File", ds_map: Dict[str, object]) -> Dict[str, object]:
    """Expose KHARMA/IHARM primitive dumps as generic r/theta/phi field names."""
    if "prims" not in ds_map or "header/prim_names" not in ds_map:
        return {"type": "explicit_datasets"}

    prims = np.asarray(ds_map["prims"])
    if prims.ndim != 4:
        return {"type": "explicit_datasets", "primitiveRejected": f"prims has shape {prims.shape}"}

    names_raw = np.asarray(ds_map["header/prim_names"])
    names = [
        (x.decode("utf-8", errors="replace") if isinstance(x, bytes) else str(x)).strip("\x00").strip().upper()
        for x in names_raw
    ]
    index = {name: i for i, name in enumerate(names)}
    required = ["RHO", "UU", "U1", "U2", "U3", "B1", "B2", "B3"]
    missing = [name for name in required if name not in index]
    if missing:
        return {"type": "explicit_datasets", "primitiveRejected": f"missing primitives: {missing}"}

    n1, n2, n3, _ = prims.shape
    startx1 = _h5_float(h5, "header/geom/startx1", _h5_float(h5, "header/startx1", 0.0))
    startx2 = _h5_float(h5, "header/geom/startx2", _h5_float(h5, "header/startx2", 0.0))
    startx3 = _h5_float(h5, "header/geom/startx3", _h5_float(h5, "header/startx3", 0.0))
    dx1 = _h5_float(h5, "header/geom/dx1", _h5_float(h5, "header/dx1", 1.0 / max(n1, 1)))
    dx2 = _h5_float(h5, "header/geom/dx2", _h5_float(h5, "header/dx2", 1.0 / max(n2, 1)))
    dx3 = _h5_float(h5, "header/geom/dx3", _h5_float(h5, "header/dx3", 2.0 * np.pi / max(n3, 1)))
    x1 = startx1 + (np.arange(n1, dtype=np.float64) + 0.5) * dx1
    x2 = startx2 + (np.arange(n2, dtype=np.float64) + 0.5) * dx2
    x3 = startx3 + (np.arange(n3, dtype=np.float64) + 0.5) * dx3

    coordinates = str(_h5_value(h5, "header/coordinates", _h5_value(h5, "header/metric", ""))).upper()
    r = np.exp(x1)
    if "FMKS" in coordinates:
        theta = _fmks_theta_from_native_x2(h5, np.full_like(x2, float(np.median(x1))), x2)
    else:
        hslope = _h5_float(h5, "header/hslope", 0.3)
        theta = np.pi * x2 + ((1.0 - hslope) * 0.5) * np.sin(2.0 * np.pi * x2)
        theta = np.clip(theta, 1.0e-6, np.pi - 1.0e-6)
    phi = np.mod(x3, 2.0 * np.pi)

    ds_map.setdefault("r", r)
    ds_map.setdefault("x1v", r)
    ds_map.setdefault("theta", theta)
    ds_map.setdefault("x2v", theta)
    ds_map.setdefault("phi", phi)
    ds_map.setdefault("x3v", phi)
    ds_map.setdefault("rho", prims[:, :, :, index["RHO"]])
    ds_map.setdefault("uu", prims[:, :, :, index["UU"]])
    ds_map.setdefault("u", prims[:, :, :, index["UU"]])
    ds_map.setdefault("vx1", prims[:, :, :, index["U1"]])
    ds_map.setdefault("vx2", prims[:, :, :, index["U2"]])
    ds_map.setdefault("vx3", prims[:, :, :, index["U3"]])
    ds_map.setdefault("B1", prims[:, :, :, index["B1"]])
    ds_map.setdefault("B2", prims[:, :, :, index["B2"]])
    ds_map.setdefault("B3", prims[:, :, :, index["B3"]])

    return {
        "type": "primitive_prims",
        "layout": "KHARMA/IHARM prims[n1,n2,n3,nprim]",
        "coordinates": coordinates,
        "primitiveNames": names,
        "coordinateMapping": "r=exp(x1); theta=MKS/FMKS native map; phi=x3",
        "shape": [int(n1), int(n2), int(n3)],
        "spin": _h5_float(h5, "header/a", _h5_float(h5, "header/geom/fmks/a", 0.0)),
    }


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


def _extract_rtheta_phi_cube(arr: np.ndarray, nr: int, nth: int, nphi: int, name: str) -> np.ndarray:
    x = np.asarray(arr, dtype=np.float64).squeeze()
    if x.ndim == 1 and x.size == nr * nth * nphi:
        x = x.reshape(nr, nth, nphi)
    if x.ndim < 3:
        raise ValueError(f"{name} must be >=3D or flattened nr*nth*nphi; got shape={x.shape}")

    r_axes = [i for i, s in enumerate(x.shape) if s == nr]
    t_axes = [i for i, s in enumerate(x.shape) if s == nth]
    p_axes = [i for i, s in enumerate(x.shape) if s == nphi]
    if not r_axes or not t_axes or not p_axes:
        raise ValueError(f"{name}: cannot find r/theta/phi axes for shape={x.shape}")

    triple: Optional[Tuple[int, int, int]] = None
    for ra in r_axes:
        for ta in t_axes:
            if ta == ra:
                continue
            for pa in p_axes:
                if pa != ra and pa != ta:
                    triple = (ra, ta, pa)
                    break
            if triple is not None:
                break
        if triple is not None:
            break
    if triple is None:
        raise ValueError(f"{name}: ambiguous r/theta/phi axis mapping for shape={x.shape}")

    x = np.moveaxis(x, list(triple), [0, 1, 2])
    if x.ndim > 3:
        x = np.nanmean(x, axis=tuple(range(3, x.ndim)))
    if x.shape != (nr, nth, nphi):
        raise ValueError(f"{name}: expected {(nr, nth, nphi)} after reduction; got {x.shape}")
    return x


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


def _interp_periodic_phi(field: np.ndarray, phi_src: np.ndarray, phi_tgt: np.ndarray) -> np.ndarray:
    f = np.asarray(field, dtype=np.float64)
    p = np.mod(np.asarray(phi_src, dtype=np.float64), 2.0 * np.pi)
    order = np.argsort(p)
    p = p[order]
    f = f[:, order]
    if p.size == 1:
        return np.repeat(f, phi_tgt.size, axis=1)

    # Remove duplicate wrapped endpoints before extending periodically.
    keep = np.ones_like(p, dtype=bool)
    keep[1:] = np.diff(p) > 1e-10
    p = p[keep]
    f = f[:, keep]
    p_ext = np.concatenate([p, p[:1] + 2.0 * np.pi])
    f_ext = np.concatenate([f, f[:, :1]], axis=1)
    pt = np.mod(phi_tgt, 2.0 * np.pi)
    out = np.empty((f.shape[0], pt.size), dtype=np.float64)
    for i in range(f.shape[0]):
        out[i] = np.interp(pt, p_ext, f_ext[i], period=2.0 * np.pi)
    return out


def _build_regular_grid_atlas(
    r_norm_1d: np.ndarray,
    phi_1d: np.ndarray,
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
    """Resample regular GRMHD r-phi fields into the renderer atlas grid.

    The older scatter/bin path is useful for unstructured bridge samples, but it
    creates vertical dash artifacts when a low-nphi primitive dump is expanded to
    a high-width atlas. This path uses wrapped phi interpolation plus radial
    interpolation so every atlas texel comes from neighboring GRMHD cells.
    """
    r_src = np.asarray(r_norm_1d, dtype=np.float64)
    order = np.argsort(r_src)
    r_src = r_src[order]
    fields = [
        np.asarray(temp_scale, dtype=np.float64)[order],
        np.asarray(density, dtype=np.float64)[order],
        np.asarray(vr_ratio, dtype=np.float64)[order],
        np.asarray(vphi_scale, dtype=np.float64)[order],
    ]
    phi_tgt = (np.arange(width, dtype=np.float64) + 0.5) / max(width, 1) * (2.0 * np.pi)
    y = (np.arange(height, dtype=np.float64) + 0.5) / max(height, 1)
    r01 = np.power(np.clip(y, 0.0, 1.0), 1.0 / max(r_warp, 1e-6))
    r_tgt = r_min + (r_max - r_min) * r01

    channels = []
    for field in fields:
        phi_interp = _interp_periodic_phi(field, phi_1d, phi_tgt)
        out = np.empty((height, width), dtype=np.float64)
        for x in range(width):
            out[:, x] = np.interp(r_tgt, r_src, phi_interp[:, x], left=phi_interp[0, x], right=phi_interp[-1, x])
        channels.append(out)

    atlas = np.zeros((height, width, 4), dtype=np.float32)
    atlas[..., 0] = np.clip(channels[0], 0.05, 20.0).astype(np.float32)
    atlas[..., 1] = np.clip(channels[1], 0.0, 1.0).astype(np.float32)
    atlas[..., 2] = np.clip(channels[2], -1.0, 1.0).astype(np.float32)
    atlas[..., 3] = np.clip(channels[3], 0.0, 4.0).astype(np.float32)
    return atlas


def _gaussian_offsets(sigma_px: float) -> Tuple[np.ndarray, np.ndarray]:
    sigma = float(max(sigma_px, 0.0))
    if sigma <= 1.0e-6:
        return np.array([0], dtype=np.int64), np.array([1.0], dtype=np.float64)
    radius = int(np.ceil(2.75 * sigma))
    radius = max(1, min(radius, 64))
    offsets = np.arange(-radius, radius + 1, dtype=np.int64)
    weights = np.exp(-0.5 * (offsets.astype(np.float64) / sigma) ** 2)
    weights /= np.sum(weights)
    return offsets, weights


def _blur_periodic_phi(field: np.ndarray, sigma_px: float) -> np.ndarray:
    offsets, weights = _gaussian_offsets(sigma_px)
    out = np.zeros_like(field, dtype=np.float64)
    for off, w in zip(offsets, weights):
        out += float(w) * np.roll(field, int(off), axis=1)
    return out


def _blur_clamped_r(field: np.ndarray, sigma_px: float) -> np.ndarray:
    offsets, weights = _gaussian_offsets(sigma_px)
    h = field.shape[0]
    rows = np.arange(h, dtype=np.int64)
    out = np.zeros_like(field, dtype=np.float64)
    for off, w in zip(offsets, weights):
        idx = np.clip(rows + int(off), 0, h - 1)
        out += float(w) * field[idx, :]
    return out


def _source_space_positive_filter(field: np.ndarray, sigma_r_px: float, sigma_phi_px: float, rms_mix: float) -> np.ndarray:
    """Filter a positive emissivity proxy in atlas source coordinates.

    This is deliberately not an image-space denoiser.  It models a finite
    photospheric/hot-skin footprint in disk (r, phi) before ray transport, so a
    single lensed ray no longer aliases one high-percentile GRMHD texel into
    dotted critical-curve artifacts.
    """
    x = np.clip(np.asarray(field, dtype=np.float64), 0.0, 1.0)
    if sigma_r_px <= 1.0e-6 and sigma_phi_px <= 1.0e-6:
        return x

    def blur(v: np.ndarray) -> np.ndarray:
        y = _blur_periodic_phi(v, sigma_phi_px)
        y = _blur_clamped_r(y, sigma_r_px)
        return y

    mean = blur(x)
    rms = np.sqrt(np.maximum(blur(x * x), 0.0))
    mix = float(np.clip(rms_mix, 0.0, 1.0))
    return np.clip((1.0 - mix) * mean + mix * rms, 0.0, 1.0)


def _append_optional_arg(cmd: List[str], flag: str, value: object, default: object = None) -> None:
    if value is None or value == "" or value == default:
        return
    cmd.extend([flag, str(value)])


def _append_bool_arg(cmd: List[str], flag: str, enabled: bool) -> None:
    if enabled:
        cmd.append(flag)


def _build_secondary_atlas(args: argparse.Namespace, output_path: Path) -> None:
    cmd = [
        sys.executable,
        str(Path(__file__).resolve()),
        "--input",
        str(Path(args.input_next).expanduser().resolve()),
        "--output",
        str(output_path),
        "--width",
        str(args.width),
        "--height",
        str(args.height),
        "--r-min",
        str(args.r_min),
        "--r-max",
        str(args.r_max),
        "--r-warp",
        str(args.r_warp),
        "--r-to-rs",
        str(args.r_to_rs),
        "--kepler-gm",
        str(args.kepler_gm),
        "--theta-index",
        str(args.theta_index),
        "--atlas-mode",
        str(args.atlas_mode),
        "--photosphere-h-over-r",
        str(args.photosphere_h_over_r),
        "--photosphere-contrast",
        str(args.photosphere_contrast),
        "--photosphere-max-ratio",
        str(args.photosphere_max_ratio),
        "--photosphere-velocity-source",
        str(args.photosphere_velocity_source),
        "--photosphere-corona-mix",
        str(args.photosphere_corona_mix),
        "--photosphere-corona-h-over-r",
        str(args.photosphere_corona_h_over_r),
        "--photosphere-density-channel",
        str(args.photosphere_density_channel),
        "--photosphere-skin-z-lo",
        str(args.photosphere_skin_z_lo),
        "--photosphere-skin-z-hi",
        str(args.photosphere_skin_z_hi),
        "--photosphere-skin-filter-r-px",
        str(args.photosphere_skin_filter_r_px),
        "--photosphere-skin-filter-phi-px",
        str(args.photosphere_skin_filter_phi_px),
        "--photosphere-skin-filter-rms-mix",
        str(args.photosphere_skin_filter_rms_mix),
        "--density-p-lo",
        str(args.density_p_lo),
        "--density-p-hi",
        str(args.density_p_hi),
    ]
    _append_optional_arg(cmd, "--r-key", args.r_key, "")
    _append_optional_arg(cmd, "--theta-key", args.theta_key, "")
    _append_optional_arg(cmd, "--phi-key", args.phi_key, "")
    _append_optional_arg(cmd, "--rho-key", args.rho_key, "")
    _append_optional_arg(cmd, "--temp-key", args.temp_key, "")
    _append_optional_arg(cmd, "--vr-key", args.vr_key, "")
    _append_optional_arg(cmd, "--vphi-key", args.vphi_key, "")
    _append_optional_arg(cmd, "--br-key", args.br_key, "")
    _append_optional_arg(cmd, "--btheta-key", args.btheta_key, "")
    _append_optional_arg(cmd, "--bphi-key", args.bphi_key, "")
    _append_bool_arg(cmd, "--theta-average", bool(args.theta_average))
    _append_bool_arg(cmd, "--temp-is-scale", bool(args.temp_is_scale))
    _append_bool_arg(cmd, "--vr-is-ratio", bool(args.vr_is_ratio))
    _append_bool_arg(cmd, "--vphi-is-scale", bool(args.vphi_is_scale))
    _append_bool_arg(cmd, "--density-log", bool(args.density_log))
    try:
        subprocess.run(cmd, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    except subprocess.CalledProcessError as exc:
        if exc.stdout:
            print(exc.stdout, file=sys.stdout, end="")
        if exc.stderr:
            print(exc.stderr, file=sys.stderr, end="")
        raise


def _blend_temporal_atlases(atlas0: np.ndarray, atlas1: np.ndarray, blend: float) -> np.ndarray:
    t = float(np.clip(blend, 0.0, 1.0))
    if t <= 0.0:
        return atlas0
    if t >= 1.0:
        return atlas1
    out = (1.0 - t) * atlas0 + t * atlas1
    # Temperature is multiplicative; blend in log space to avoid dimming hot
    # patches while interpolating between adjacent simulation dumps.
    out[..., 0] = np.exp((1.0 - t) * np.log(np.maximum(atlas0[..., 0], 1e-30))
                         + t * np.log(np.maximum(atlas1[..., 0], 1e-30)))
    return out.astype(np.float32)


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


def _finite_percentiles(x: np.ndarray, points: Iterable[float]) -> Dict[str, float]:
    arr = np.asarray(x, dtype=np.float64)
    arr = arr[np.isfinite(arr)]
    if arr.size == 0:
        return {f"p{p:g}": 0.0 for p in points}
    return {f"p{p:g}": float(np.nanpercentile(arr, p)) for p in points}


def _row_median_normalize(x: np.ndarray, contrast: float, max_ratio: float) -> np.ndarray:
    y = np.asarray(x, dtype=np.float64)
    med = np.nanmedian(y, axis=1, keepdims=True)
    med = np.maximum(med, 1e-300)
    log_rel = np.log(np.maximum(y, 1e-300) / med)
    max_log = np.log(max(max_ratio, 1.001))
    log_rel = np.clip(log_rel * max(contrast, 0.0), -max_log, max_log)
    return np.exp(log_rel)


def _robust_texture_channel(x: np.ndarray, contrast: float, max_sigma: float) -> np.ndarray:
    y = np.log(np.maximum(np.asarray(x, dtype=np.float64), 1e-300))
    med = np.nanmedian(y, axis=1, keepdims=True)
    mad = np.nanmedian(np.abs(y - med), axis=1, keepdims=True)
    sigma = np.maximum(1.4826 * mad, 1e-6)
    z = np.clip((y - med) / sigma, -max(max_sigma, 1e-3), max(max_sigma, 1e-3))
    return np.clip(0.5 + 0.5 * np.tanh(0.55 * max(contrast, 0.0) * z), 0.0, 1.0)


def _positive_tail_activity_channel(x: np.ndarray, contrast: float, z_lo: float, z_hi: float) -> np.ndarray:
    """Row-local positive activity map for optically thin hot-skin emission.

    Unlike the older robust texture channel, this intentionally does not encode
    below-median structure as dark texture. Values below the local row baseline
    become zero; only positive stress/heating excursions survive as emissivity.
    """
    y = np.log(np.maximum(np.asarray(x, dtype=np.float64), 1e-300))
    med = np.nanmedian(y, axis=1, keepdims=True)
    mad = np.nanmedian(np.abs(y - med), axis=1, keepdims=True)
    sigma = np.maximum(1.4826 * mad, 1e-6)
    z = max(contrast, 0.0) * (y - med) / sigma
    lo = float(z_lo)
    hi = max(float(z_hi), lo + 1e-6)
    t = np.clip((z - lo) / (hi - lo), 0.0, 1.0)
    return (t * t * (3.0 - 2.0 * t)).astype(np.float64)


def _theta_cell_width(theta: np.ndarray) -> np.ndarray:
    th = np.asarray(theta, dtype=np.float64)
    if th.size == 1:
        return np.ones_like(th)
    edges = np.empty(th.size + 1, dtype=np.float64)
    edges[1:-1] = 0.5 * (th[:-1] + th[1:])
    edges[0] = th[0] - 0.5 * (th[1] - th[0])
    edges[-1] = th[-1] + 0.5 * (th[-1] - th[-2])
    edges = np.clip(edges, 0.0, np.pi)
    return np.maximum(np.diff(edges), 1e-9)


def _temperature_proxy(temp: np.ndarray, rho: np.ndarray, temp_key: str, temp_is_scale: bool) -> np.ndarray:
    if temp_is_scale:
        return np.maximum(np.asarray(temp, dtype=np.float64), 1e-30)
    base = temp_key.rsplit("/", 1)[-1].lower()
    if base in {"u", "uu", "prs", "press", "pressure", "internal_energy"}:
        return np.maximum(temp, 1e-30) / np.maximum(rho, 1e-30)
    return np.maximum(np.asarray(temp, dtype=np.float64), 1e-30)


def _build_photosphere_fields(
    r_norm_1d: np.ndarray,
    theta_1d: np.ndarray,
    rho: np.ndarray,
    temp: np.ndarray,
    temp_key: str,
    vr: np.ndarray,
    vphi: np.ndarray,
    br: Optional[np.ndarray],
    btheta: Optional[np.ndarray],
    bphi: Optional[np.ndarray],
    temp_is_scale: bool,
    h_over_r: float,
    contrast: float,
    max_ratio: float,
    velocity_source: str,
    corona_mix: float,
    corona_h_over_r: float,
    density_channel: str,
    skin_z_lo: float,
    skin_z_hi: float,
) -> Tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray, Dict[str, object]]:
    """Reduce a 3D GRMHD primitive dump to thin-surface atlas channels.

    The atlas is not a new fake texture: it is a rendering closure that preserves
    phi-dependent GRMHD column/stress variations while using the renderer's thin
    relativistic surface transport for visible photospheric emission.
    """
    rr = np.asarray(r_norm_1d, dtype=np.float64)
    th = np.asarray(theta_1d, dtype=np.float64)
    rho = np.maximum(np.asarray(rho, dtype=np.float64), 0.0)
    thetae = _temperature_proxy(np.asarray(temp, dtype=np.float64), rho, temp_key, temp_is_scale)
    br_arr = np.zeros_like(rho) if br is None else np.asarray(br, dtype=np.float64)
    bt_arr = np.zeros_like(rho) if btheta is None else np.asarray(btheta, dtype=np.float64)
    bp_arr = np.zeros_like(rho) if bphi is None else np.asarray(bphi, dtype=np.float64)

    z_over_r = np.cos(th)[None, :, None]
    sigma = max(float(h_over_r), 1e-4)
    thin_weight = np.exp(-0.5 * (z_over_r / sigma) ** 2)
    # Transition-layer support for a positive hot-skin emissivity channel.  This
    # is a rendering-source closure: it samples GRMHD stress/heating above the
    # thermalized midplane without making the whole 3D torus the visible body.
    skin_inner_sigma = max(0.72 * sigma, 1e-4)
    skin_outer_sigma = max(2.55 * sigma, skin_inner_sigma + 1e-4)
    skin_weight = np.maximum(
        np.exp(-0.5 * (z_over_r / skin_outer_sigma) ** 2)
        - np.exp(-0.5 * (z_over_r / skin_inner_sigma) ** 2),
        0.0,
    )
    corona_sigma = max(float(corona_h_over_r), sigma + 1e-4)
    broad_weight = np.exp(-0.5 * (z_over_r / corona_sigma) ** 2)
    high_latitude = np.clip(1.0 - thin_weight, 0.0, 1.0)
    corona_weight = broad_weight * high_latitude
    dtheta = _theta_cell_width(th)[None, :, None]
    metric_weight = np.maximum(np.sin(th)[None, :, None], 1e-6) * dtheta
    w = thin_weight * metric_weight
    wc = corona_weight * metric_weight

    bmag = np.sqrt(np.maximum(br_arr * br_arr + bt_arr * bt_arr + bp_arr * bp_arr, 0.0))
    maxwell = np.maximum(-br_arr * bp_arr, 0.0) + 0.15 * np.abs(br_arr * bp_arr)
    b2 = np.maximum(br_arr * br_arr + bt_arr * bt_arr + bp_arr * bp_arr, 0.0)
    shear = np.power(np.maximum(rr, 1.0), -1.5)[:, None]
    sigma_col = np.sum(rho * w, axis=1)
    stress_col = np.sum(maxwell * rho * w, axis=1)
    hot_col = np.sum(rho * np.power(np.maximum(thetae, 1e-12), 1.15) * (1.0 + 0.15 * bmag) * w, axis=1)
    flux_proxy = np.maximum(0.72 * stress_col * shear + 0.28 * hot_col, 1e-300)
    skin_emissivity_proxy = np.maximum(
        np.sum(
            np.power(np.maximum(rho, 1e-30), 0.45)
            * np.power(np.maximum(thetae, 1e-12), 1.80)
            * np.power(np.maximum(b2, 1e-30), 0.55)
            * np.power(np.maximum(maxwell, 1e-30), 0.28)
            * skin_weight
            * metric_weight,
            axis=1,
        )
        * shear,
        1e-300,
    )
    corona_proxy = np.maximum(
        np.sum(
            rho
            * np.power(np.maximum(thetae, 1e-12), 1.45)
            * (1.0 + 1.35 * bmag)
            * wc,
            axis=1,
        )
        * shear,
        1e-300,
    )
    corona_rel = _row_median_normalize(corona_proxy, contrast=max(contrast, 1.0), max_ratio=max_ratio)
    corona_mix_clamped = float(np.clip(corona_mix, 0.0, 1.0))
    if corona_mix_clamped > 0.0:
        flux_proxy = np.maximum(
            flux_proxy * ((1.0 - corona_mix_clamped) + corona_mix_clamped * corona_rel),
            1e-300,
        )

    # The renderer already owns the radial Novikov-Thorne-like profile. Keep the
    # GRMHD atlas as a row-local modulation so turbulent phi structure survives
    # without double-counting a code-unit radial luminosity calibration.
    flux_rel = _row_median_normalize(flux_proxy, contrast=contrast, max_ratio=max_ratio)
    temp_scale = np.clip(np.power(flux_rel, 0.25), 0.35, 2.25)
    if density_channel == "hot-skin":
        density = _positive_tail_activity_channel(
            skin_emissivity_proxy,
            contrast=max(contrast, 0.0),
            z_lo=skin_z_lo,
            z_hi=skin_z_hi,
        )
    elif density_channel == "stress":
        density = _robust_texture_channel(flux_proxy, contrast=contrast, max_sigma=3.0)
    else:
        density = _robust_texture_channel(flux_proxy * np.maximum(sigma_col, 1e-300), contrast=contrast, max_sigma=3.0)

    if velocity_source == "data":
        vk = np.sqrt(1.0 / np.maximum(rr[:, None], 1e-12))
        vel_weight = rho * w
        denom = np.maximum(np.sum(vel_weight, axis=1), 1e-300)
        vr_mean = np.sum(np.asarray(vr, dtype=np.float64) * vel_weight, axis=1) / denom
        vphi_mean = np.sum(np.asarray(vphi, dtype=np.float64) * vel_weight, axis=1) / denom
        vr_ratio = np.clip(vr_mean / np.maximum(vk, 1e-12), -0.6, 0.6)
        vphi_scale = np.clip(vphi_mean / np.maximum(vk, 1e-12), 0.25, 1.75)
    else:
        vr_ratio = np.zeros_like(temp_scale)
        vphi_scale = np.ones_like(temp_scale)

    phi_rel_std = np.nanstd(flux_proxy, axis=1) / np.maximum(np.nanmean(flux_proxy, axis=1), 1e-300)
    meta = {
        "closure": "vertical thin-weighted GRMHD column/stress photosphere atlas",
        "hOverR": float(h_over_r),
        "contrast": float(contrast),
        "maxRatio": float(max_ratio),
        "velocitySource": velocity_source,
        "coronaMix": corona_mix_clamped,
        "coronaHOverR": float(corona_h_over_r),
        "channels": {
            "x": "T_eff modulation = row-normalized flux_proxy^(1/4)",
            "y": "selected density/activity channel: column, stress, or positive hot-skin emissivity",
            "z": "v_r/v_k if requested, otherwise 0",
            "w": "v_phi/v_k if requested, otherwise 1",
        },
        "proxies": {
            "Sigma": _finite_percentiles(sigma_col, [1.0, 50.0, 95.0, 99.0]),
            "flux": _finite_percentiles(flux_proxy, [1.0, 50.0, 95.0, 99.0]),
            "coronaProxy": _finite_percentiles(corona_proxy, [1.0, 50.0, 95.0, 99.0]),
            "skinEmissivityProxy": _finite_percentiles(skin_emissivity_proxy, [1.0, 50.0, 95.0, 99.0]),
            "activityChannel": _finite_percentiles(density, [1.0, 50.0, 95.0, 99.0]),
            "thetae": _finite_percentiles(thetae, [1.0, 50.0, 95.0, 99.0]),
            "bmag": _finite_percentiles(bmag, [1.0, 50.0, 95.0, 99.0]),
            "phiRelStdMedian": float(np.nanmedian(phi_rel_std)),
            "phiRelStdP95": float(np.nanpercentile(phi_rel_std, 95.0)),
        },
        "densityChannel": density_channel,
        "skinActivityZLo": float(skin_z_lo),
        "skinActivityZHi": float(skin_z_hi),
    }
    return temp_scale, density, vr_ratio, vphi_scale, meta


def main() -> None:
    ap = argparse.ArgumentParser(description="Build disk_atlas.bin from an offline GRMHD HDF5 snapshot")
    ap.add_argument("--input", required=True, help="input HDF5 snapshot path")
    ap.add_argument("--input-next", default="", help="optional next HDF5 snapshot for temporal atlas interpolation")
    ap.add_argument("--time-blend", type=float, default=0.0, help="blend factor between --input and --input-next")
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
    ap.add_argument("--theta-key", default="", help="theta dataset key/path for photosphere atlas (auto if omitted)")
    ap.add_argument("--phi-key", default="", help="azimuth dataset key/path (auto if omitted)")
    ap.add_argument("--rho-key", default="", help="density dataset key/path (auto if omitted)")
    ap.add_argument("--temp-key", default="", help="temperature dataset key/path (auto if omitted)")
    ap.add_argument("--vr-key", default="", help="radial velocity dataset key/path (auto if omitted)")
    ap.add_argument("--vphi-key", default="", help="azimuth velocity dataset key/path (auto if omitted)")
    ap.add_argument("--br-key", default="", help="radial magnetic-field dataset key/path for photosphere mode")
    ap.add_argument("--btheta-key", default="", help="theta/vertical magnetic-field dataset key/path for photosphere mode")
    ap.add_argument("--bphi-key", default="", help="azimuth magnetic-field dataset key/path for photosphere mode")
    ap.add_argument("--atlas-mode", choices=["slice", "photosphere"], default="slice", help="HDF5-to-atlas mapping mode")
    ap.add_argument("--photosphere-h-over-r", type=float, default=0.08, help="vertical Gaussian H/R used only for GRMHD photosphere reduction")
    ap.add_argument("--photosphere-contrast", type=float, default=1.35, help="row-local GRMHD flux contrast gain for photosphere mode")
    ap.add_argument("--photosphere-max-ratio", type=float, default=6.0, help="maximum row-local flux modulation ratio in photosphere mode")
    ap.add_argument("--photosphere-velocity-source", choices=["none", "data"], default="none", help="whether atlas velocity channels use GRMHD primitive velocity proxies")
    ap.add_argument("--photosphere-corona-mix", type=float, default=0.0, help="mix high-|z| hot/magnetized 3D flow structure into the photosphere source proxy")
    ap.add_argument("--photosphere-corona-h-over-r", type=float, default=0.35, help="broad vertical H/R used for high-latitude hot-flow proxy")
    ap.add_argument(
        "--photosphere-density-channel",
        choices=["column", "stress", "hot-skin"],
        default="column",
        help="atlas y channel: legacy column texture, stress texture, or positive hot-skin activity",
    )
    ap.add_argument("--photosphere-skin-z-lo", type=float, default=0.75, help="row-local z-score lower edge for hot-skin activity channel")
    ap.add_argument("--photosphere-skin-z-hi", type=float, default=2.35, help="row-local z-score upper edge for hot-skin activity channel")
    ap.add_argument("--photosphere-skin-filter-r-px", type=float, default=0.0, help="source-space radial Gaussian sigma in final atlas pixels for hot-skin activity")
    ap.add_argument("--photosphere-skin-filter-phi-px", type=float, default=0.0, help="source-space azimuthal Gaussian sigma in final atlas pixels for hot-skin activity")
    ap.add_argument("--photosphere-skin-filter-rms-mix", type=float, default=0.55, help="mix between mean and RMS when filtering positive hot-skin activity")
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
    if args.time_blend < 0.0 or args.time_blend > 1.0:
        raise ValueError("time-blend must be in [0, 1]")
    if args.input_next and not Path(args.input_next).expanduser().exists():
        raise ValueError(f"input-next not found: {args.input_next}")
    if args.photosphere_h_over_r <= 0:
        raise ValueError("photosphere-h-over-r must be > 0")
    if args.photosphere_max_ratio <= 1.0:
        raise ValueError("photosphere-max-ratio must be > 1")
    if not (0.0 <= args.photosphere_corona_mix <= 1.0):
        raise ValueError("photosphere-corona-mix must be in [0, 1]")
    if args.photosphere_corona_h_over_r <= 0:
        raise ValueError("photosphere-corona-h-over-r must be > 0")
    if args.photosphere_skin_z_hi <= args.photosphere_skin_z_lo:
        raise ValueError("photosphere-skin-z-hi must be greater than photosphere-skin-z-lo")
    if args.photosphere_skin_filter_r_px < 0.0 or args.photosphere_skin_filter_phi_px < 0.0:
        raise ValueError("photosphere skin filter sigmas must be >= 0")
    if not (0.0 <= args.photosphere_skin_filter_rms_mix <= 1.0):
        raise ValueError("photosphere-skin-filter-rms-mix must be in [0, 1]")
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

        primitive_meta = _inject_primitive_dump(h5, ds_map)

        r_key = _resolve_key(ds_map, args.r_key, ["r", "radius", "x1v", "x1", "X1", "grid/r"], "radius")
        theta_key = ""
        if args.atlas_mode == "photosphere":
            theta_key = _resolve_key(ds_map, args.theta_key, ["theta", "x2v", "x2", "X2", "grid/theta"], "theta")
        phi_key = _resolve_key(ds_map, args.phi_key, ["phi", "x3v", "x3", "X3", "grid/phi"], "phi")
        rho_key = _resolve_key(ds_map, args.rho_key, ["rho", "density", "dens", "RHO", "Density"], "density")
        temp_key = _resolve_key(
            ds_map,
            args.temp_key,
            ["temp_scale", "temperature", "temp", "Theta", "theta_e", "Te", "uu", "u", "prs", "press", "pressure"],
            "temperature",
        )
        vr_key = _resolve_key(ds_map, args.vr_key, ["vr_ratio", "vr", "v_r", "vx1", "u1", "v1", "vel1"], "radial velocity")
        vphi_key = _resolve_key(ds_map, args.vphi_key, ["vphi_scale", "vphi", "v_phi", "vx3", "u3", "v3", "vel3"], "azimuth velocity")
        br_key = _resolve_optional_key(ds_map, args.br_key, ["B1", "br", "b_r", "B_r", "b1"])
        btheta_key = _resolve_optional_key(ds_map, args.btheta_key, ["B2", "btheta", "b_theta", "B_theta", "bz", "Bz", "b2"])
        bphi_key = _resolve_optional_key(ds_map, args.bphi_key, ["B3", "bphi", "b_phi", "B_phi", "b3"])

        r = _coord_1d(np.asarray(ds_map[r_key]), "r")
        phi = _coord_1d(np.asarray(ds_map[phi_key]), "phi")
        if r.size < 2 or phi.size < 2:
            raise ValueError(f"invalid coordinate sizes: r={r.size}, phi={phi.size}")

        nr = int(r.size)
        nphi = int(phi.size)
        r_norm_1d = np.asarray(r, dtype=np.float64) * args.r_to_rs
        phi_1d = np.mod(np.asarray(phi, dtype=np.float64), 2.0 * np.pi)

        if args.atlas_mode == "photosphere":
            theta = _coord_1d(np.asarray(ds_map[theta_key]), "theta")
            nth = int(theta.size)
            if nth < 2:
                raise ValueError(f"invalid theta coordinate size: theta={nth}")
            rho_3d = _extract_rtheta_phi_cube(np.asarray(ds_map[rho_key]), nr, nth, nphi, "rho")
            temp_3d = _extract_rtheta_phi_cube(np.asarray(ds_map[temp_key]), nr, nth, nphi, "temp")
            vr_3d = _extract_rtheta_phi_cube(np.asarray(ds_map[vr_key]), nr, nth, nphi, "vr")
            vphi_3d = _extract_rtheta_phi_cube(np.asarray(ds_map[vphi_key]), nr, nth, nphi, "vphi")
            br_3d = _extract_rtheta_phi_cube(np.asarray(ds_map[br_key]), nr, nth, nphi, "br") if br_key else None
            btheta_3d = _extract_rtheta_phi_cube(np.asarray(ds_map[btheta_key]), nr, nth, nphi, "btheta") if btheta_key else None
            bphi_3d = _extract_rtheta_phi_cube(np.asarray(ds_map[bphi_key]), nr, nth, nphi, "bphi") if bphi_key else None
            temp_scale_2d, density_2d, vr_ratio_2d, vphi_scale_2d, photosphere_meta = _build_photosphere_fields(
                r_norm_1d=r_norm_1d,
                theta_1d=np.asarray(theta, dtype=np.float64),
                rho=rho_3d,
                temp=temp_3d,
                temp_key=temp_key,
                vr=vr_3d,
                vphi=vphi_3d,
                br=br_3d,
                btheta=btheta_3d,
                bphi=bphi_3d,
                temp_is_scale=args.temp_is_scale,
                h_over_r=args.photosphere_h_over_r,
                contrast=args.photosphere_contrast,
                max_ratio=args.photosphere_max_ratio,
                velocity_source=args.photosphere_velocity_source,
                corona_mix=args.photosphere_corona_mix,
                corona_h_over_r=args.photosphere_corona_h_over_r,
                density_channel=args.photosphere_density_channel,
                skin_z_lo=args.photosphere_skin_z_lo,
                skin_z_hi=args.photosphere_skin_z_hi,
            )
        else:
            rho_2d = _extract_rphi_plane(np.asarray(ds_map[rho_key]), nr, nphi, args.theta_index, args.theta_average, "rho")
            temp_2d = _extract_rphi_plane(np.asarray(ds_map[temp_key]), nr, nphi, args.theta_index, args.theta_average, "temp")
            vr_2d = _extract_rphi_plane(np.asarray(ds_map[vr_key]), nr, nphi, args.theta_index, args.theta_average, "vr")
            vphi_2d = _extract_rphi_plane(np.asarray(ds_map[vphi_key]), nr, nphi, args.theta_index, args.theta_average, "vphi")
            rr_slice, _ = np.meshgrid(r_norm_1d, phi_1d, indexing="ij")
            v_k = np.sqrt(args.kepler_gm / np.maximum(rr_slice, 1e-12))
            temp_scale_2d = _normalize_temperature(temp_2d, rr_slice, args.temp_is_scale)
            density_2d = _normalize_density(rho_2d, args.density_log, args.density_p_lo, args.density_p_hi)
            vr_ratio_2d = _velocity_to_ratio(vr_2d, v_k, args.vr_is_ratio)
            vphi_scale_2d = _velocity_to_ratio(vphi_2d, v_k, args.vphi_is_scale)
            photosphere_meta = {}

    rr, pp = np.meshgrid(r_norm_1d, phi_1d, indexing="ij")

    if args.atlas_mode == "photosphere":
        atlas = _build_regular_grid_atlas(
            r_norm_1d=r_norm_1d,
            phi_1d=phi_1d,
            temp_scale=temp_scale_2d,
            density=density_2d,
            vr_ratio=vr_ratio_2d,
            vphi_scale=vphi_scale_2d,
            width=args.width,
            height=args.height,
            r_min=args.r_min,
            r_max=args.r_max,
            r_warp=args.r_warp,
        )
    else:
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

    skin_filter_meta: Dict[str, object] = {
        "enabled": False,
        "sigmaRPx": float(args.photosphere_skin_filter_r_px),
        "sigmaPhiPx": float(args.photosphere_skin_filter_phi_px),
        "rmsMix": float(args.photosphere_skin_filter_rms_mix),
    }
    if (
        args.atlas_mode == "photosphere"
        and args.photosphere_density_channel == "hot-skin"
        and (args.photosphere_skin_filter_r_px > 0.0 or args.photosphere_skin_filter_phi_px > 0.0)
    ):
        before = atlas[..., 1].astype(np.float64)
        atlas[..., 1] = _source_space_positive_filter(
            before,
            sigma_r_px=args.photosphere_skin_filter_r_px,
            sigma_phi_px=args.photosphere_skin_filter_phi_px,
            rms_mix=args.photosphere_skin_filter_rms_mix,
        ).astype(np.float32)
        skin_filter_meta = {
            **skin_filter_meta,
            "enabled": True,
            "before": _finite_percentiles(before, [50.0, 90.0, 95.0, 99.0, 99.7]),
            "after": _finite_percentiles(atlas[..., 1], [50.0, 90.0, 95.0, 99.0, 99.7]),
            "interpretation": "finite positive hot-skin source footprint in atlas disk coordinates",
        }

    temporal_meta: Dict[str, object] = {
        "enabled": False,
        "inputNext": "",
        "timeBlend": 0.0,
    }
    if args.input_next and args.time_blend > 0.0:
        tmp_path = Path(tempfile.mkstemp(prefix="blackhole_grmhd_atlas_next.", suffix=".bin")[1])
        try:
            _build_secondary_atlas(args, tmp_path)
            atlas_next = np.fromfile(tmp_path, dtype=np.float32).reshape(atlas.shape)
            atlas = _blend_temporal_atlases(atlas, atlas_next, args.time_blend)
            temporal_meta = {
                "enabled": True,
                "inputNext": str(Path(args.input_next).expanduser().resolve()),
                "timeBlend": float(args.time_blend),
                "blend": "temperature log-space; density and velocity linear",
            }
        finally:
            tmp_path.unlink(missing_ok=True)
            Path(str(tmp_path) + ".json").unlink(missing_ok=True)

    atlas.tofile(out_path)
    meta = {
        "width": args.width,
        "height": args.height,
        "format": "float4",
        "channels": ["temp_scale", "density", "vr_ratio", "vphi_scale"],
        "source": str(in_path),
        "temporal": temporal_meta,
        "atlasMode": args.atlas_mode,
        "rNormMin": args.r_min,
        "rNormMax": args.r_max,
        "rNormWarp": args.r_warp,
        "rToRs": args.r_to_rs,
        "keplerGm": args.kepler_gm,
        "thetaIndex": args.theta_index,
        "thetaAverage": bool(args.theta_average),
        "keys": {
            "r": r_key,
            "theta": theta_key if args.atlas_mode == "photosphere" else "",
            "phi": phi_key,
            "rho": rho_key,
            "temp": temp_key,
            "vr": vr_key,
            "vphi": vphi_key,
            "br": br_key or "",
            "btheta": btheta_key or "",
            "bphi": bphi_key or "",
        },
        "primitive": primitive_meta,
        "photosphere": photosphere_meta,
        "skinFilter": skin_filter_meta,
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
