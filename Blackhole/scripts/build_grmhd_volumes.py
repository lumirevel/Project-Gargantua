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
            return sorted(m, key=len)[0]

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


def _h5_int(h5: "h5py.File", key: str, default: int) -> int:
    value = _h5_value(h5, key, default)
    try:
        return int(value)
    except Exception:
        return int(default)


def _fmks_theta_from_native_x2(h5: "h5py.File", x1: np.ndarray, x2: np.ndarray) -> np.ndarray:
    """Approximate FMKS native x2 -> Kerr-Schild theta using pyharm's public formula.

    This is used only to place primitive dumps on the renderer's r-phi-z texture grid.
    It does not replace a full metric/tetrad transform for covariant transfer.
    """
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
    """Expose KHARMA/IHARM primitive dumps as the generic datasets used below."""
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
        "velocityInterpretation": "U1/U2/U3 imported from primitive dump; auto mode converts them with an approximate Kerr-Schild normalization",
        "coordinateMapping": "r=exp(x1); theta=MKS/FMKS native map; phi=x3",
        "shape": [int(n1), int(n2), int(n3)],
        "spin": _h5_float(h5, "header/a", _h5_float(h5, "header/geom/fmks/a", 0.0)),
    }


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


def _extract_rtheta_phi_cube(
    arr: np.ndarray,
    nr: int,
    nth: int,
    nphi: int,
    theta_index: int,
    theta_average: bool,
    name: str,
) -> np.ndarray:
    x = np.asarray(arr, dtype=np.float64).squeeze()
    if x.ndim == 1 and x.size == nr * nth * nphi:
        x = x.reshape(nr, nth, nphi)
    if x.ndim < 3:
        raise ValueError(f"{name} must be >=3D or flattened nr*nth*nphi; got shape={x.shape}")

    r_axes = [i for i, s in enumerate(x.shape) if s == nr]
    t_axes = [i for i, s in enumerate(x.shape) if s == nth]
    p_axes = [i for i, s in enumerate(x.shape) if s == nphi]
    if not r_axes or not t_axes or not p_axes:
        raise ValueError(
            f"{name}: cannot find r/theta/phi axes for "
            f"nr={nr}, nth={nth}, nphi={nphi}, shape={x.shape}"
        )

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
        raise ValueError(f"{name}: ambiguous axis mapping for shape={x.shape}")

    r_axis, t_axis, p_axis = triple
    x = np.moveaxis(x, [r_axis, t_axis, p_axis], [0, 1, 2])

    if x.ndim > 3:
        if theta_average:
            x = np.nanmean(x, axis=tuple(range(3, x.ndim)))
        else:
            slicer: List[object] = [slice(None), slice(None), slice(None)]
            for ax in range(3, x.ndim):
                n = x.shape[ax]
                idx = theta_index if theta_index >= 0 else (n // 2)
                idx = max(0, min(n - 1, idx))
                slicer.append(idx)
            x = x[tuple(slicer)]

    if x.shape == (nr, nth, nphi):
        return x
    raise ValueError(f"{name}: expected {(nr, nth, nphi)} after reduction; got {x.shape}")


def _load_optional_plane(
    ds_map: Dict[str, object],
    explicit: str,
    candidates: Iterable[str],
    nr: int,
    nphi: int,
    theta_index: int,
    theta_average: bool,
    label: str,
) -> Tuple[Optional[str], Optional[np.ndarray]]:
    key = _resolve_optional_key(ds_map, explicit, candidates)
    if key is None:
        return None, None
    arr = _extract_rphi_plane(np.asarray(ds_map[key]), nr, nphi, theta_index, theta_average, label)
    return key, arr


def _load_optional_cube(
    ds_map: Dict[str, object],
    explicit: str,
    candidates: Iterable[str],
    nr: int,
    nth: int,
    nphi: int,
    theta_index: int,
    theta_average: bool,
    label: str,
) -> Tuple[Optional[str], Optional[np.ndarray]]:
    key = _resolve_optional_key(ds_map, explicit, candidates)
    if key is None:
        return None, None
    arr = _extract_rtheta_phi_cube(
        np.asarray(ds_map[key]),
        nr,
        nth,
        nphi,
        theta_index,
        theta_average,
        label,
    )
    return key, arr


def _key_basename(key: Optional[str]) -> str:
    if not key:
        return ""
    return key.rsplit("/", 1)[-1].lower()


def _thetae_from_energy_density(u: np.ndarray, rho: np.ndarray, scale: float) -> np.ndarray:
    # GRMHD snapshots usually store internal energy/pressure as a density-like code-unit
    # quantity. A dimensionless temperature proxy should therefore be proportional to u/rho,
    # not u alone. A future electron model can replace this prescription.
    return scale * np.maximum(u, 1e-30) / np.maximum(rho, 1e-30)


def _electron_model_name(requested: str, has_b: bool) -> str:
    name = requested.lower()
    if name == "auto":
        return "r-beta" if has_b else "single-temp"
    return name


def _thetae_from_rbeta_prescription(
    u: np.ndarray,
    rho: np.ndarray,
    br: np.ndarray,
    bphi: np.ndarray,
    bz: np.ndarray,
    scale: float,
    gamma_ad: float,
    r_low: float,
    r_high: float,
) -> tuple[np.ndarray, Dict[str, float]]:
    """Derive an electron-temperature proxy using the common R_low/R_high model.

    The GRMHD primitive dump used here does not provide a fully covariant b^mu or
    electron entropy. This remains a code-unit bridge, but it is materially better
    than treating the total gas temperature u/rho as the electron temperature
    everywhere: high-beta disk material becomes ion-hot/electron-cool, while
    magnetized low-beta regions keep hotter electrons and preserve coronal
    structure for optically thin emission diagnostics.
    """
    gas_theta = _thetae_from_energy_density(u, rho, scale)
    p_gas = np.maximum((gamma_ad - 1.0) * np.asarray(u, dtype=np.float64), 0.0)
    b2 = (
        np.asarray(br, dtype=np.float64) * np.asarray(br, dtype=np.float64)
        + np.asarray(bphi, dtype=np.float64) * np.asarray(bphi, dtype=np.float64)
        + np.asarray(bz, dtype=np.float64) * np.asarray(bz, dtype=np.float64)
    )
    p_mag = np.maximum(0.5 * b2, 1e-300)
    plasma_beta = p_gas / p_mag
    beta2 = plasma_beta * plasma_beta
    ti_over_te = (r_low + r_high * beta2) / np.maximum(1.0 + beta2, 1e-300)
    thetae = gas_theta / np.maximum(ti_over_te, 1e-12)
    thetae = np.maximum(thetae, 1e-12)
    stats = {
        "gasThetaMedian": float(np.nanpercentile(gas_theta, 50.0)),
        "gasThetaP95": float(np.nanpercentile(gas_theta, 95.0)),
        "thetaeMedian": float(np.nanpercentile(thetae, 50.0)),
        "thetaeP95": float(np.nanpercentile(thetae, 95.0)),
        "plasmaBetaMedian": float(np.nanpercentile(plasma_beta, 50.0)),
        "plasmaBetaP95": float(np.nanpercentile(plasma_beta, 95.0)),
        "tiOverTeMedian": float(np.nanpercentile(ti_over_te, 50.0)),
        "tiOverTeP95": float(np.nanpercentile(ti_over_te, 95.0)),
    }
    return thetae, stats


def _velocity_mode_for_key(key: Optional[str], requested: str) -> str:
    if requested != "auto":
        return requested
    base = _key_basename(key)
    if base in {"u1", "u2", "u3", "ur", "uth", "uphi"}:
        return "four-velocity"
    return "beta"


def _velocity_to_beta(
    v: Optional[np.ndarray],
    u0: Optional[np.ndarray],
    key: Optional[str],
    requested_mode: str,
    label: str,
) -> Tuple[np.ndarray, str]:
    if v is None:
        raise ValueError(f"{label} velocity array is missing")
    mode = _velocity_mode_for_key(key, requested_mode)
    out = np.asarray(v, dtype=np.float64)
    if mode == "four-velocity":
        if u0 is None:
            raise ValueError(
                f"{label} uses a four-velocity-like key '{key}', but u0/u^t is missing. "
                "Provide --u0-key or use --disk-grmhd-velocity-mode beta only for already-normalized 3-velocities."
            )
        out = out / np.maximum(np.asarray(u0, dtype=np.float64), 1e-30)
    return np.clip(out, -0.999, 0.999), mode


def _primitive_ks_u_to_cylindrical_beta(
    u1: np.ndarray,
    u2: np.ndarray,
    u3: np.ndarray,
    r: np.ndarray,
    theta: np.ndarray,
    spin: float,
) -> Tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Approximate KHARMA/IHARM primitive U1..U3 -> cylindrical beta proxies.

    The public dumps used here do not include u^t or metric grids. For rendering
    diagnostics, solve g_mu_nu u^mu u^nu=-1 using a spherical Kerr-Schild metric
    at the native r/theta coordinates, then convert coordinate velocities to a
    local cylindrical proxy. This is not a full FMKS tetrad transform, but it is
    much closer to the primitive meaning than treating U^i as beta directly.
    """
    ur = np.asarray(u1, dtype=np.float64)
    uth = np.asarray(u2, dtype=np.float64)
    uph = np.asarray(u3, dtype=np.float64)
    rr = np.asarray(r, dtype=np.float64)[:, None, None]
    th = np.asarray(theta, dtype=np.float64)[None, :, None]
    a = float(np.clip(spin, -0.999, 0.999))

    sin_th = np.sin(th)
    cos_th = np.cos(th)
    sin2 = np.maximum(sin_th * sin_th, 1e-12)
    sigma = np.maximum(rr * rr + a * a * cos_th * cos_th, 1e-12)
    two_r_over_sigma = 2.0 * rr / sigma

    g_tt = -(1.0 - two_r_over_sigma)
    g_tr = two_r_over_sigma
    g_tphi = -2.0 * a * rr * sin2 / sigma
    g_rr = 1.0 + two_r_over_sigma
    g_rphi = -a * sin2 * (1.0 + two_r_over_sigma)
    g_thth = sigma
    g_phiphi = sin2 * (sigma + a * a * sin2 * (1.0 + two_r_over_sigma))

    b = 2.0 * (g_tr * ur + g_tphi * uph)
    c = (
        g_rr * ur * ur
        + g_thth * uth * uth
        + g_phiphi * uph * uph
        + 2.0 * g_rphi * ur * uph
        + 1.0
    )
    disc = np.maximum(b * b - 4.0 * g_tt * c, 1e-30)
    denom = 2.0 * g_tt
    denom = np.where(np.abs(denom) > 1e-30, denom, -1e-30)
    ut = (-b - np.sqrt(disc)) / denom
    ut = np.where(np.isfinite(ut) & (ut > 1e-12), ut, 1.0)

    drdt = ur / ut
    dthdt = uth / ut
    dphidt = uph / ut

    v_r_cyl = sin_th * drdt + rr * cos_th * dthdt
    v_z_cyl = cos_th * drdt - rr * sin_th * dthdt
    v_phi = rr * sin_th * dphidt

    beta2 = v_r_cyl * v_r_cyl + v_phi * v_phi + v_z_cyl * v_z_cyl
    scale = np.ones_like(beta2)
    mask = beta2 > (0.999 * 0.999)
    scale[mask] = 0.999 / np.sqrt(np.maximum(beta2[mask], 1e-30))
    return (
        np.clip(v_r_cyl * scale, -0.999, 0.999),
        np.clip(v_phi * scale, -0.999, 0.999),
        np.clip(v_z_cyl * scale, -0.999, 0.999),
    )


def _json_attr_value(value: object) -> object:
    arr = np.asarray(value)
    if arr.shape == ():
        item = arr.item()
        if isinstance(item, bytes):
            return item.decode("utf-8", errors="replace")
        if isinstance(item, np.generic):
            return item.item()
        return item
    return arr.tolist() if arr.size <= 16 else str(value)


def _finite_stats(x: np.ndarray) -> Dict[str, float]:
    arr = np.asarray(x, dtype=np.float64)
    arr = arr[np.isfinite(arr)]
    if arr.size == 0:
        return {"min": 0.0, "p01": 0.0, "median": 0.0, "p99": 0.0, "max": 0.0}
    return {
        "min": float(np.min(arr)),
        "p01": float(np.percentile(arr, 1.0)),
        "median": float(np.median(arr)),
        "p99": float(np.percentile(arr, 99.0)),
        "max": float(np.max(arr)),
    }


def _emissive_auto_r_max(
    r_norm_src: np.ndarray,
    rho: np.ndarray,
    thetae: np.ndarray,
    bmag: np.ndarray,
    source_format: Dict[str, object],
) -> Tuple[float, Dict[str, object]]:
    """Choose a useful default outer radius for wide primitive GRMHD dumps.

    Public KHARMA/IHARM dumps often extend to r~10^3 while the visible emitting
    structure is concentrated in the inner tens of rg. Even with radial warping,
    keeping the full simulation domain wastes most volume texels on faint outer
    flow. This crop only applies when the user did not pass --r-max.
    """
    r = np.asarray(r_norm_src, dtype=np.float64)
    src_r_min = float(np.nanmin(r))
    src_r_max = float(np.nanmax(r))
    reason = {
        "mode": "full-source",
        "sourceRMax": src_r_max,
        "selectedRMax": src_r_max,
    }
    if source_format.get("type") != "primitive_prims" or src_r_max <= 200.0:
        return src_r_max, reason

    # Thermal proxy is intentionally broader than synchrotron-like B-weighted
    # proxies, so the crop preserves lensed outer disk context while still
    # allocating most radial texels to the emitting inner flow.
    proxy = np.maximum(rho, 0.0) * np.maximum(thetae, 1e-12)
    if bmag.size == proxy.size:
        b_norm = bmag / max(float(np.nanpercentile(np.maximum(bmag, 0.0), 95.0)), 1e-30)
        proxy *= np.power(np.maximum(b_norm, 1e-6), 0.20)
    axes = tuple(range(1, proxy.ndim))
    prof = np.nanmean(np.maximum(proxy, 0.0), axis=axes)
    weight = np.maximum(prof, 0.0) * np.maximum(np.gradient(r), 1e-12)
    if not np.isfinite(weight).all() or float(np.sum(weight)) <= 0.0:
        selected = min(src_r_max, 96.0)
        reason.update({"mode": "primitive-default", "selectedRMax": selected})
        return selected, reason

    cdf = np.cumsum(weight) / max(float(np.sum(weight)), 1e-30)
    idx95 = int(np.searchsorted(cdf, 0.95, side="left"))
    idx98 = int(np.searchsorted(cdf, 0.98, side="left"))
    r95 = float(r[min(max(idx95, 0), r.size - 1)])
    r98 = float(r[min(max(idx98, 0), r.size - 1)])
    # Keep the crop tied to the measured emissive distribution. A hard 80rs
    # minimum preserves context, but it also lets faint, low-contrast outer
    # material dominate close-up visible renders as a broad pale slab. Use a
    # modest guard above r98 instead: enough room for lensed outer context, but
    # still mostly allocating samples to the radiating inner flow.
    selected = min(src_r_max, max(48.0, min(160.0, r98 * 1.08)))
    reason.update({
        "mode": "primitive-emissive-crop",
        "proxy": "mean(rho * thetae * normalized_B^0.20)",
        "r95": r95,
        "r98": r98,
        "selectedRMax": selected,
    })
    return selected, reason


def _warped_radial_grid(r_min: float, r_max: float, nr: int, r_warp: float) -> np.ndarray:
    """Renderer-matched radial grid for GRMHD volumes.

    r_warp < 1 allocates more texels to the inner flow. The Metal sampler maps
    physical radius back with ur_tex = ((r-r_min)/(r_max-r_min)) ** r_warp.
    """
    n = max(int(nr), 1)
    if n == 1:
        return np.array([0.5 * (float(r_min) + float(r_max))], dtype=np.float64)
    y = np.linspace(0.0, 1.0, n, dtype=np.float64)
    r01 = np.power(np.clip(y, 0.0, 1.0), 1.0 / max(float(r_warp), 1e-6))
    return float(r_min) + (float(r_max) - float(r_min)) * r01


def _phi_variation_stats(field: np.ndarray, phi_axis: int = 1) -> Dict[str, float]:
    """Relative phi contrast after import; near-zero means the source is effectively axisymmetric."""
    arr = np.asarray(field, dtype=np.float64)
    if arr.ndim < 2:
        return {"medianRelStd": 0.0, "p95RelStd": 0.0, "maxRelStd": 0.0, "profileRelStd": 0.0}
    arr = np.moveaxis(arr, phi_axis, -1)
    finite = np.isfinite(arr)
    safe = np.where(finite, arr, np.nan)
    mean_phi = np.nanmean(safe, axis=-1)
    std_phi = np.nanstd(safe, axis=-1)
    rel = std_phi / np.maximum(np.abs(mean_phi), 1e-30)
    rel = rel[np.isfinite(rel)]
    profile = np.nanmean(safe, axis=tuple(range(arr.ndim - 1)))
    profile_rel = float(np.nanstd(profile) / max(abs(np.nanmean(profile)), 1e-30)) if profile.size > 0 else 0.0
    if rel.size == 0:
        return {"medianRelStd": 0.0, "p95RelStd": 0.0, "maxRelStd": 0.0, "profileRelStd": profile_rel}
    return {
        "medianRelStd": float(np.percentile(rel, 50.0)),
        "p95RelStd": float(np.percentile(rel, 95.0)),
        "maxRelStd": float(np.max(rel)),
        "profileRelStd": profile_rel,
    }


def _phi_variation_band_stats(
    field: np.ndarray,
    r_values: np.ndarray,
    z_values: np.ndarray,
    phi_axis: int = 1,
    r_axis: int = 2,
    z_axis: int = 0,
) -> list[Dict[str, object]]:
    """Band-limited phi contrast after import for judging snapshot usefulness."""
    arr = np.asarray(field, dtype=np.float64)
    if arr.ndim != 3:
        return []
    arr = np.moveaxis(arr, (z_axis, phi_axis, r_axis), (0, 1, 2))
    safe = np.where(np.isfinite(arr), arr, np.nan)
    mean_phi = np.nanmean(safe, axis=1)
    std_phi = np.nanstd(safe, axis=1)
    rel = std_phi / np.maximum(np.abs(mean_phi), 1e-30)
    r = np.asarray(r_values, dtype=np.float64)
    z = np.asarray(z_values, dtype=np.float64)
    if r.size != rel.shape[1] or z.size != rel.shape[0]:
        return []

    r_bands = [(0.0, 0.25), (0.25, 0.50), (0.50, 0.75), (0.75, 1.0)]
    z_bands = [
        ("midplane", 0.00, 0.20),
        ("body", 0.20, 0.65),
        ("all_z", 0.00, 1.00),
    ]
    r_min = float(np.nanmin(r)) if r.size else 0.0
    r_max = float(np.nanmax(r)) if r.size else 1.0
    z_abs = np.abs(z)
    z_max = max(float(np.nanmax(z_abs)) if z_abs.size else 1.0, 1e-30)
    out: list[Dict[str, object]] = []
    for r0, r1 in r_bands:
        lo = r_min + (r_max - r_min) * r0
        hi = r_min + (r_max - r_min) * r1
        r_mask = (r >= lo) & (r <= hi)
        for label, z0, z1 in z_bands:
            z_mask = (z_abs / z_max >= z0) & (z_abs / z_max <= z1)
            vals = rel[np.ix_(z_mask, r_mask)]
            vals = vals[np.isfinite(vals)]
            if vals.size == 0:
                continue
            out.append(
                {
                    "rFrac": [float(r0), float(r1)],
                    "rRange": [float(lo), float(hi)],
                    "zBand": label,
                    "medianRelStd": float(np.percentile(vals, 50.0)),
                    "p95RelStd": float(np.percentile(vals, 95.0)),
                    "maxRelStd": float(np.max(vals)),
                    "cells": int(vals.size),
                }
            )
    return out


def _snapshot_suitability(phi_variation: Dict[str, Dict[str, float]], synthetic_b: bool, native_3d: bool) -> Dict[str, object]:
    """Conservative data-quality flags for visible GRMHD rendering."""
    rho_p95 = float(phi_variation.get("rho", {}).get("p95RelStd", 0.0))
    thetae_p95 = float(phi_variation.get("thetae", {}).get("p95RelStd", 0.0))
    beta_p95 = float(phi_variation.get("betaMagnitude", {}).get("p95RelStd", 0.0))
    b_p95 = float(phi_variation.get("bMagnitude", {}).get("p95RelStd", 0.0))
    flow_score = max(rho_p95, thetae_p95)
    dynamics_score = max(beta_p95, b_p95)
    warnings: list[str] = []
    if flow_score < 0.02:
        warnings.append("rho/thetae phi contrast is weak; visible turbulent structure will be intrinsically limited")
    if dynamics_score < 0.01:
        warnings.append("B/velocity phi contrast is weak; Doppler/synchrotron flow texture will look axisymmetric")
    if synthetic_b:
        warnings.append("magnetic field is synthetic; synchrotron and magnetization diagnostics are not predictive")
    if not native_3d:
        warnings.append("source was mapped through a 2D vertical fallback; vertical flow structure is inferred")
    if flow_score >= 0.08 and dynamics_score >= 0.03 and native_3d and not synthetic_b:
        rating = "good"
    elif flow_score >= 0.02 or dynamics_score >= 0.01:
        rating = "limited"
    else:
        rating = "poor"
    return {
        "rating": rating,
        "flowPhiP95": flow_score,
        "dynamicsPhiP95": dynamics_score,
        "warnings": warnings,
    }


def _amplify_phi_deviation_positive(
    field: np.ndarray,
    factor: float,
    phi_axis: int,
    floor: float,
    max_ratio: float,
    smooth_strength: float = 0.0,
    smooth_passes: int = 1,
    rz_smooth_strength: float = 0.0,
    rz_smooth_passes: int = 1,
) -> np.ndarray:
    """Amplify existing azimuthal deviations while preserving each cell's phi mean.

    The source snapshots used for the visible-flow path often have weak azimuthal
    contrast.  A hard-clipped linear boost makes high-contrast cells turn into
    flat plateaus that render as patchwork.  This keeps the old linear response
    for small deviations, but uses a smooth limiter before re-normalizing the
    phi-ring mean.
    """
    if abs(factor - 1.0) < 1e-12 and smooth_strength <= 0.0 and rz_smooth_strength <= 0.0:
        return np.asarray(field, dtype=np.float64)
    arr = np.moveaxis(np.asarray(field, dtype=np.float64), phi_axis, -1)
    floor_safe = max(float(floor), 1e-300)
    mean = np.nanmean(arr, axis=-1, keepdims=True)
    mean = np.maximum(mean, floor_safe)
    ratio = np.maximum(arr, floor_safe) / mean
    min_ratio = np.clip(floor_safe / mean, 1e-300, 1.0)
    pos_limit = max(float(max_ratio) - 1.0, 1e-12)
    neg_limit = np.maximum(1.0 - min_ratio, 1e-12)

    if abs(factor - 1.0) < 1e-12:
        ratio_amp = ratio
    else:
        delta = factor * (ratio - 1.0)
        ratio_amp = np.where(
            delta >= 0.0,
            1.0 + pos_limit * np.tanh(delta / pos_limit),
            1.0 - neg_limit * np.tanh((-delta) / neg_limit),
        )
    if smooth_strength > 0.0 and smooth_passes > 0:
        ratio_amp = 1.0 + _smooth_periodic_phi_residual(
            ratio_amp - 1.0,
            smooth_strength,
            smooth_passes,
        )
    if rz_smooth_strength > 0.0 and rz_smooth_passes > 0:
        ratio_amp = 1.0 + _smooth_nonperiodic_residual_axes(
            ratio_amp - 1.0,
            rz_smooth_strength,
            rz_smooth_passes,
            tuple(range(max(ratio_amp.ndim - 1, 0))),
        )
    # Preserve the original phi-ring average after the non-linear soft limit.
    ratio_mean = np.nanmean(ratio_amp, axis=-1, keepdims=True)
    ratio_amp = ratio_amp / np.maximum(ratio_mean, 1e-300)
    ratio_amp = np.clip(ratio_amp, min_ratio, max_ratio)
    out = mean * ratio_amp
    return np.moveaxis(np.maximum(out, floor_safe), -1, phi_axis)


def _amplify_phi_deviation_linear(
    field: np.ndarray,
    factor: float,
    phi_axis: int,
    limit: Optional[float] = None,
    smooth_strength: float = 0.0,
    smooth_passes: int = 1,
    rz_smooth_strength: float = 0.0,
    rz_smooth_passes: int = 1,
) -> np.ndarray:
    """Amplify existing signed azimuthal deviations around the phi mean."""
    if abs(factor - 1.0) < 1e-12 and smooth_strength <= 0.0 and rz_smooth_strength <= 0.0:
        return np.asarray(field, dtype=np.float64)
    arr = np.moveaxis(np.asarray(field, dtype=np.float64), phi_axis, -1)
    mean = np.nanmean(arr, axis=-1, keepdims=True)
    residual = arr - mean
    if smooth_strength > 0.0 and smooth_passes > 0:
        residual = _smooth_periodic_phi_residual(residual, smooth_strength, smooth_passes)
    if rz_smooth_strength > 0.0 and rz_smooth_passes > 0:
        residual = _smooth_nonperiodic_residual_axes(
            residual,
            rz_smooth_strength,
            rz_smooth_passes,
            tuple(range(max(residual.ndim - 1, 0))),
        )
    out = mean + factor * residual
    if limit is not None:
        out = np.clip(out, -limit, limit)
    return np.moveaxis(out, -1, phi_axis)


def _smooth_periodic_phi_residual(residual: np.ndarray, strength: float, passes: int) -> np.ndarray:
    """Band-limit phi residuals without changing each r-z phi-ring mean.

    This is a preprocessing-only diagnostic for coarse evolved snapshots: the
    zero-mean azimuthal residual is low-passed with periodic boundaries, then
    blended back.  It reduces cell-scale striping that gravitational lensing
    repeats into rings while preserving the large-scale GRMHD contrast.
    """
    strength = float(np.clip(strength, 0.0, 1.0))
    passes = max(int(passes), 0)
    if strength <= 0.0 or passes <= 0:
        return residual
    smoothed = np.asarray(residual, dtype=np.float64)
    for _ in range(passes):
        smoothed = (
            0.25 * np.roll(smoothed, 1, axis=-1)
            + 0.5 * smoothed
            + 0.25 * np.roll(smoothed, -1, axis=-1)
        )
    return residual * (1.0 - strength) + smoothed * strength


def _smooth_nonperiodic_residual_axes(
    residual: np.ndarray,
    strength: float,
    passes: int,
    axes: Tuple[int, ...],
) -> np.ndarray:
    """Band-limit non-periodic r/z residuals while preserving phi-ring means."""
    strength = float(np.clip(strength, 0.0, 1.0))
    passes = max(int(passes), 0)
    if strength <= 0.0 or passes <= 0 or not axes:
        return residual
    smoothed = np.asarray(residual, dtype=np.float64)
    for _ in range(passes):
        for axis in axes:
            if smoothed.shape[axis] <= 1:
                continue
            pad = [(0, 0)] * smoothed.ndim
            pad[axis] = (1, 1)
            padded = np.pad(smoothed, pad, mode="edge")
            center = [slice(None)] * smoothed.ndim
            prev = [slice(None)] * smoothed.ndim
            next_ = [slice(None)] * smoothed.ndim
            center[axis] = slice(1, -1)
            prev[axis] = slice(0, -2)
            next_[axis] = slice(2, None)
            smoothed = (
                0.25 * padded[tuple(prev)]
                + 0.5 * padded[tuple(center)]
                + 0.25 * padded[tuple(next_)]
            )
    return residual * (1.0 - strength) + smoothed * strength


def _resample_periodic_phi_2d(field: np.ndarray, out_nphi: int) -> np.ndarray:
    src_nphi = field.shape[1]
    if src_nphi == out_nphi:
        return field.copy()
    x_out = np.linspace(0.0, float(src_nphi), out_nphi, endpoint=False, dtype=np.float64)
    x0 = np.floor(x_out).astype(np.int64) % src_nphi
    x1 = (x0 + 1) % src_nphi
    t = x_out - np.floor(x_out)
    return field[:, x0] * (1.0 - t)[None, :] + field[:, x1] * t[None, :]


def _resample_rphi(field: np.ndarray, r_src: np.ndarray, r_dst: np.ndarray, out_nphi: int) -> np.ndarray:
    phi_resampled = _resample_periodic_phi_2d(field, out_nphi)
    if np.array_equal(r_src, r_dst):
        return phi_resampled
    out = np.empty((r_dst.size, out_nphi), dtype=np.float64)
    for j in range(out_nphi):
        out[:, j] = np.interp(
            r_dst,
            r_src,
            phi_resampled[:, j],
            left=phi_resampled[0, j],
            right=phi_resampled[-1, j],
        )
    return out


def _resample_periodic_phi_3d(cube: np.ndarray, out_nphi: int) -> np.ndarray:
    src_nphi = cube.shape[2]
    if src_nphi == out_nphi:
        return cube.copy()
    x_out = np.linspace(0.0, float(src_nphi), out_nphi, endpoint=False, dtype=np.float64)
    x0 = np.floor(x_out).astype(np.int64) % src_nphi
    x1 = (x0 + 1) % src_nphi
    t = x_out - np.floor(x_out)
    return cube[:, :, x0] * (1.0 - t)[None, None, :] + cube[:, :, x1] * t[None, None, :]


def _sample_cube_to_rphiz(
    cube: np.ndarray,
    r_src: np.ndarray,
    theta_src: np.ndarray,
    r_dst: np.ndarray,
    z_dst: np.ndarray,
    out_nphi: int,
) -> np.ndarray:
    r_arr = np.asarray(r_src, dtype=np.float64)
    t_arr = np.asarray(theta_src, dtype=np.float64)
    f = np.asarray(cube, dtype=np.float64)

    if r_arr[0] > r_arr[-1]:
        r_arr = r_arr[::-1]
        f = f[::-1, :, :]
    if t_arr[0] > t_arr[-1]:
        t_arr = t_arr[::-1]
        f = f[:, ::-1, :]

    f = _resample_periodic_phi_3d(f, out_nphi)

    nr_out = r_dst.size
    nz_out = z_dst.size
    nth_src = t_arr.size
    f_r = np.empty((nr_out, nth_src, out_nphi), dtype=np.float64)
    for j in range(out_nphi):
        for k in range(nth_src):
            f_r[:, k, j] = np.interp(
                r_dst,
                r_arr,
                f[:, k, j],
                left=f[0, k, j],
                right=f[-1, k, j],
            )

    out = np.zeros((nz_out, out_nphi, nr_out), dtype=np.float64)
    for i, rval in enumerate(r_dst):
        rabs = max(abs(float(rval)), 1e-12)
        mu = np.clip(z_dst / rabs, -1.0, 1.0)
        theta_q = np.arccos(mu)
        valid = np.abs(z_dst) <= rabs
        for j in range(out_nphi):
            col = np.interp(theta_q, t_arr, f_r[i, :, j], left=f_r[i, 0, j], right=f_r[i, -1, j])
            col[~valid] = 0.0
            out[:, j, i] = col
    return out


def main() -> None:
    ap = argparse.ArgumentParser(description="Build GRMHD dual volumes (vol0/vol1) for scalar GRRT rendering.")
    ap.add_argument("--input", required=True, help="input HDF5 snapshot path")
    ap.add_argument("--vol0", required=True, help="output vol0 .bin path (float4: log_rho, log_thetae, v_r, v_phi)")
    ap.add_argument("--vol1", required=True, help="output vol1 .bin path (float4: v_z, B_r, B_phi, B_z)")
    ap.add_argument("--meta", required=True, help="output metadata .json path")
    ap.add_argument("--nr", type=int, default=128, help="output radial bins")
    ap.add_argument("--nphi", type=int, default=256, help="output azimuth bins")
    ap.add_argument("--nz", type=int, default=72, help="output vertical bins")
    ap.add_argument("--r-min", type=float, default=-1.0, help="minimum r/rs in output (default: auto)")
    ap.add_argument("--r-max", type=float, default=-1.0, help="maximum r/rs in output (default: auto)")
    ap.add_argument("--r-warp", type=float, default=0.65, help="radial texture warp; <1 allocates more bins to the inner flow")
    ap.add_argument("--z-max", type=float, default=0.35, help="maximum |z|/rs in output")
    ap.add_argument("--r-to-rs", type=float, default=1.0, help="multiplier to convert input radius to r/rs")
    ap.add_argument("--theta-index", type=int, default=-1, help="theta index for extra dimensions (-1=mid)")
    ap.add_argument("--theta-average", action="store_true", help="average extra axes instead of slicing")
    ap.add_argument("--theta-key", default="", help="theta/polar coordinate dataset key/path")
    ap.add_argument("--native-3d", choices=["auto", "on", "off"], default="auto", help="use native 3D (r,theta,phi) sampling path")
    ap.add_argument("--u-to-thetae", type=float, default=1.0, help="scale factor for thetae when deriving from internal energy u")
    ap.add_argument(
        "--electron-model",
        choices=["auto", "single-temp", "r-beta"],
        default="auto",
        help="electron-temperature prescription when thetae is derived from u; auto uses r-beta when B fields are available",
    )
    ap.add_argument("--electron-r-low", type=float, default=1.0, help="R_low for R_low/R_high electron-temperature prescription")
    ap.add_argument("--electron-r-high", type=float, default=20.0, help="R_high for R_low/R_high electron-temperature prescription")
    ap.add_argument("--adiabatic-gamma", type=float, default=4.0 / 3.0, help="gas gamma used to estimate pressure from internal energy")
    ap.add_argument(
        "--phi-contrast",
        type=float,
        default=1.0,
        help="diagnostic multiplier for existing phi deviations; 1 keeps source data unchanged",
    )
    ap.add_argument(
        "--phi-contrast-max-ratio",
        type=float,
        default=64.0,
        help="safety clamp for positive-field phi contrast amplification",
    )
    ap.add_argument(
        "--phi-residual-smooth",
        type=float,
        default=0.0,
        help=(
            "blend amount in [0,1] for periodic low-pass filtering of phi residuals; "
            "preserves each r-z phi mean and reduces coarse-cell striping"
        ),
    )
    ap.add_argument(
        "--phi-residual-smooth-passes",
        type=int,
        default=1,
        help="number of [0.25,0.5,0.25] periodic low-pass passes applied to phi residuals",
    )
    ap.add_argument(
        "--rz-residual-smooth",
        type=float,
        default=0.0,
        help=(
            "blend amount in [0,1] for non-periodic low-pass filtering of r/z residuals; "
            "preserves phi-ring means and reduces radial/vertical coarse-cell banding"
        ),
    )
    ap.add_argument(
        "--rz-residual-smooth-passes",
        type=int,
        default=1,
        help="number of [0.25,0.5,0.25] edge-padded low-pass passes applied to r/z residuals",
    )
    ap.add_argument("--list-datasets", action="store_true", help="list dataset keys and exit")
    ap.add_argument("--r-key", default="", help="radius dataset key/path")
    ap.add_argument("--phi-key", default="", help="azimuth dataset key/path")
    ap.add_argument("--rho-key", default="", help="density dataset key/path")
    ap.add_argument("--thetae-key", default="", help="electron temperature dataset key/path")
    ap.add_argument("--u-key", default="", help="internal energy dataset key/path (used when thetae is absent)")
    ap.add_argument("--pressure-key", default="", help="gas pressure dataset key/path for diagnostics")
    ap.add_argument("--bsq-key", default="", help="b^2 dataset key/path for diagnostics")
    ap.add_argument("--sigma-key", default="", help="magnetization dataset key/path for diagnostics")
    ap.add_argument("--u0-key", default="", help="time component of four-velocity for u^i/u^0 conversion")
    ap.add_argument(
        "--velocity-mode",
        choices=["auto", "beta", "four-velocity"],
        default="auto",
        help="interpret velocity fields as normalized 3-velocity beta or contravariant four-velocity",
    )
    ap.add_argument("--vr-key", default="", help="radial velocity dataset key/path")
    ap.add_argument("--vphi-key", default="", help="azimuth velocity dataset key/path")
    ap.add_argument("--vz-key", default="", help="vertical velocity dataset key/path")
    ap.add_argument("--br-key", default="", help="radial magnetic field dataset key/path")
    ap.add_argument("--bphi-key", default="", help="azimuth magnetic field dataset key/path")
    ap.add_argument("--bz-key", default="", help="vertical magnetic field dataset key/path")
    ap.add_argument("--allow-synthetic-b", action="store_true", help="allow synthetic magnetic proxy if B fields are absent")
    ap.add_argument("--vertical-density-scale", type=float, default=0.34, help="(2D fallback only) vertical density profile scale")
    ap.add_argument("--vertical-thetae-drop", type=float, default=0.18, help="(2D fallback only) thetae reduction at |z|=zmax")
    ap.add_argument("--vertical-vphi-drop", type=float, default=0.18, help="(2D fallback only) v_phi reduction at |z|=zmax")
    ap.add_argument("--vertical-vel-scale", type=float, default=0.55, help="(2D fallback only) v_r/v_z attenuation scale")
    ap.add_argument("--vertical-b-scale", type=float, default=0.45, help="(2D fallback only) B-field attenuation scale")
    args = ap.parse_args()

    if h5py is None:
        raise RuntimeError("h5py is required. install with: python3 -m pip install h5py")
    if args.nr < 2 or args.nphi < 4 or args.nz < 2:
        raise ValueError("nr/nphi/nz are too small")
    if args.r_to_rs <= 0:
        raise ValueError("r-to-rs must be > 0")
    if args.z_max <= 0:
        raise ValueError("z-max must be > 0")
    if args.u_to_thetae <= 0:
        raise ValueError("u-to-thetae must be > 0")
    if args.electron_r_low <= 0 or args.electron_r_high <= 0:
        raise ValueError("electron R_low/R_high must be > 0")
    if not (1.0 < args.adiabatic_gamma <= 2.0):
        raise ValueError("adiabatic-gamma must be in (1, 2]")
    if not np.isfinite(args.phi_contrast) or args.phi_contrast < 0.0:
        raise ValueError("phi-contrast must be finite and >= 0")
    if not np.isfinite(args.phi_contrast_max_ratio) or args.phi_contrast_max_ratio < 1.0:
        raise ValueError("phi-contrast-max-ratio must be finite and >= 1")
    if not np.isfinite(args.phi_residual_smooth) or not (0.0 <= args.phi_residual_smooth <= 1.0):
        raise ValueError("phi-residual-smooth must be finite and in [0, 1]")
    if args.phi_residual_smooth_passes < 0:
        raise ValueError("phi-residual-smooth-passes must be >= 0")
    if not np.isfinite(args.rz_residual_smooth) or not (0.0 <= args.rz_residual_smooth <= 1.0):
        raise ValueError("rz-residual-smooth must be finite and in [0, 1]")
    if args.rz_residual_smooth_passes < 0:
        raise ValueError("rz-residual-smooth-passes must be >= 0")

    in_path = Path(args.input).expanduser().resolve()
    vol0_path = Path(args.vol0).expanduser().resolve()
    vol1_path = Path(args.vol1).expanduser().resolve()
    meta_path = Path(args.meta).expanduser().resolve()

    thetae_key: Optional[str] = None
    u_key: Optional[str] = None
    pressure_key: Optional[str] = None
    bsq_key: Optional[str] = None
    sigma_key: Optional[str] = None
    u0_key: Optional[str] = None
    vr_key: Optional[str] = None
    vphi_key: Optional[str] = None
    vz_key: Optional[str] = None
    br_key: Optional[str] = None
    bphi_key: Optional[str] = None
    bz_key: Optional[str] = None
    synthetic_b = False
    use_native_3d = False
    native_3d_reason = ""
    theta_key_used: Optional[str] = None
    velocity_modes: Dict[str, str] = {}
    source_attrs: Dict[str, object] = {}
    source_format: Dict[str, object] = {}
    radial_range: Dict[str, object] = {}
    sidecar_stats: Dict[str, Dict[str, float]] = {}
    consistency_stats: Dict[str, Dict[str, float]] = {}
    thetae_prescription: Dict[str, object] = {}

    with h5py.File(in_path, "r") as h5:
        source_attrs = {str(k): _json_attr_value(v) for k, v in h5.attrs.items()}
        ds_map = _collect_datasets(h5)
        if not ds_map:
            raise ValueError(f"no datasets found in {in_path}")
        source_format = _inject_primitive_dump(h5, ds_map)
        if args.list_datasets:
            for name in sorted(ds_map.keys()):
                ds = ds_map[name]
                print(f"{name}\tshape={tuple(ds.shape)}\tdtype={ds.dtype}")
            return

        r_key = _resolve_key(ds_map, args.r_key, ["r", "radius", "x1v", "x1", "X1", "grid/r"], "radius")
        phi_key = _resolve_key(ds_map, args.phi_key, ["phi", "x3v", "x3", "X3", "grid/phi"], "phi")
        rho_key = _resolve_key(ds_map, args.rho_key, ["rho", "density", "dens", "RHO", "Density"], "density")
        theta_key = _resolve_optional_key(ds_map, args.theta_key, ["theta", "th", "x2v", "x2", "X2", "grid/theta"])
        theta_key_used = theta_key

        r = _coord_1d(np.asarray(ds_map[r_key]), "r")
        phi = _coord_1d(np.asarray(ds_map[phi_key]), "phi")
        theta = _coord_1d(np.asarray(ds_map[theta_key]), "theta") if theta_key is not None else None
        nr_src = int(r.size)
        nphi_src = int(phi.size)
        if nr_src < 2 or nphi_src < 2:
            raise ValueError(f"invalid coordinate sizes: r={nr_src}, phi={nphi_src}")

        rho_3d: Optional[np.ndarray] = None
        if args.native_3d != "off":
            if theta is None:
                if args.native_3d == "on":
                    raise ValueError("native-3d=on requires a theta coordinate (use --theta-key)")
                native_3d_reason = "theta coordinate missing"
            else:
                nth_src = int(theta.size)
                if nth_src < 2:
                    if args.native_3d == "on":
                        raise ValueError("native-3d=on requires theta size >= 2")
                    native_3d_reason = "theta size < 2"
                else:
                    try:
                        rho_3d = _extract_rtheta_phi_cube(
                            np.asarray(ds_map[rho_key]),
                            nr_src,
                            nth_src,
                            nphi_src,
                            args.theta_index,
                            args.theta_average,
                            "rho",
                        )
                        use_native_3d = True
                    except Exception as exc:
                        if args.native_3d == "on":
                            raise
                        native_3d_reason = f"rho 3D mapping unavailable: {exc}"

        if use_native_3d:
            assert theta is not None
            nth_src = int(theta.size)
            assert rho_3d is not None

            thetae_key, thetae_3d = _load_optional_cube(
                ds_map,
                args.thetae_key,
                ["thetae", "theta_e", "Thetae", "Theta", "Te", "electron_temp", "temp_e"],
                nr_src,
                nth_src,
                nphi_src,
                args.theta_index,
                args.theta_average,
                "thetae",
            )
            u_key, u_3d = _load_optional_cube(
                ds_map,
                args.u_key,
                ["u", "uu", "internal_energy", "eps", "prs", "press", "pressure"],
                nr_src,
                nth_src,
                nphi_src,
                args.theta_index,
                args.theta_average,
                "u",
            )
            thetae_from_u_3d = thetae_3d is None and u_3d is not None
            if thetae_3d is None:
                if u_3d is None:
                    thetae_3d = np.full((nr_src, nth_src, nphi_src), 0.08, dtype=np.float64)
                    thetae_prescription = {
                        "type": "constant_floor",
                        "description": "thetae fallback constant 0.08",
                    }
                else:
                    thetae_3d = _thetae_from_energy_density(u_3d, rho_3d, args.u_to_thetae)
                    thetae_prescription = {
                        "type": "u_over_rho",
                        "description": "thetae = u_to_thetae * max(u, floor) / max(rho, floor)",
                    }
            else:
                thetae_prescription = {
                    "type": "dataset",
                    "description": "thetae dataset used directly",
                }

            pressure_key, pressure_3d = _load_optional_cube(
                ds_map,
                args.pressure_key,
                ["p", "press", "pressure", "prs"],
                nr_src,
                nth_src,
                nphi_src,
                args.theta_index,
                args.theta_average,
                "pressure",
            )
            bsq_key, bsq_3d = _load_optional_cube(
                ds_map,
                args.bsq_key,
                ["bsq", "b2", "b_squared", "magnetic_pressure_2"],
                nr_src,
                nth_src,
                nphi_src,
                args.theta_index,
                args.theta_average,
                "bsq",
            )
            sigma_key, sigma_3d = _load_optional_cube(
                ds_map,
                args.sigma_key,
                ["sigma", "magnetization"],
                nr_src,
                nth_src,
                nphi_src,
                args.theta_index,
                args.theta_average,
                "sigma",
            )

            u0_key, u0_3d = _load_optional_cube(
                ds_map,
                args.u0_key,
                ["u0", "ut", "u_t", "ucon0"],
                nr_src,
                nth_src,
                nphi_src,
                args.theta_index,
                args.theta_average,
                "u0",
            )

            vr_key, vr_3d = _load_optional_cube(
                ds_map,
                args.vr_key,
                ["vr", "v_r", "vx1", "u1", "v1", "vel1"],
                nr_src,
                nth_src,
                nphi_src,
                args.theta_index,
                args.theta_average,
                "v_r",
            )
            vphi_key, vphi_3d = _load_optional_cube(
                ds_map,
                args.vphi_key,
                ["vphi", "v_phi", "vx3", "u3", "v3", "vel3"],
                nr_src,
                nth_src,
                nphi_src,
                args.theta_index,
                args.theta_average,
                "v_phi",
            )
            vz_key, vz_3d = _load_optional_cube(
                ds_map,
                args.vz_key,
                ["vz", "v_z", "vx2", "u2", "v2", "vel2"],
                nr_src,
                nth_src,
                nphi_src,
                args.theta_index,
                args.theta_average,
                "v_z",
            )
            br_key, br_3d = _load_optional_cube(
                ds_map,
                args.br_key,
                ["Br", "B_r", "B1", "bx1", "b1"],
                nr_src,
                nth_src,
                nphi_src,
                args.theta_index,
                args.theta_average,
                "B_r",
            )
            bphi_key, bphi_3d = _load_optional_cube(
                ds_map,
                args.bphi_key,
                ["Bphi", "B_phi", "B3", "bx3", "b3"],
                nr_src,
                nth_src,
                nphi_src,
                args.theta_index,
                args.theta_average,
                "B_phi",
            )
            bz_key, bz_3d = _load_optional_cube(
                ds_map,
                args.bz_key,
                ["Bz", "B_z", "B2", "bx2", "b2"],
                nr_src,
                nth_src,
                nphi_src,
                args.theta_index,
                args.theta_average,
                "B_z",
            )

            vr_3d = np.zeros_like(rho_3d) if vr_3d is None else vr_3d
            vphi_3d = np.zeros_like(rho_3d) if vphi_3d is None else vphi_3d
            vz_3d = np.zeros_like(rho_3d) if vz_3d is None else vz_3d
            if (
                source_format.get("type") == "primitive_prims"
                and args.velocity_mode == "auto"
                and u0_3d is None
            ):
                vr_3d, vphi_3d, vz_3d = _primitive_ks_u_to_cylindrical_beta(
                    vr_3d,
                    vz_3d,
                    vphi_3d,
                    np.asarray(r, dtype=np.float64),
                    np.asarray(theta, dtype=np.float64),
                    float(source_format.get("spin", 0.0)),
                )
                velocity_modes["vr"] = "primitive-ks-normalized-cylindrical"
                velocity_modes["vphi"] = "primitive-ks-normalized-cylindrical"
                velocity_modes["vz"] = "primitive-ks-normalized-cylindrical"
            else:
                vr_3d, velocity_modes["vr"] = _velocity_to_beta(vr_3d, u0_3d, vr_key, args.velocity_mode, "v_r")
                vphi_3d, velocity_modes["vphi"] = _velocity_to_beta(vphi_3d, u0_3d, vphi_key, args.velocity_mode, "v_phi")
                vz_3d, velocity_modes["vz"] = _velocity_to_beta(vz_3d, u0_3d, vz_key, args.velocity_mode, "v_z")
            if br_3d is None and bphi_3d is None and bz_3d is None:
                if not args.allow_synthetic_b:
                    raise ValueError(
                        "magnetic datasets are missing (Br/Bphi/Bz). "
                        "Provide physically consistent B fields, or pass --allow-synthetic-b explicitly."
                    )
                synthetic_b = True
                b_eq = np.sqrt(np.maximum(np.maximum(rho_3d, 1e-30) * np.maximum(thetae_3d, 1e-8), 1e-20))
                br_3d = 0.02 * b_eq
                bphi_3d = 0.35 * b_eq
                bz_3d = 0.06 * b_eq
            else:
                br_3d = np.zeros_like(rho_3d) if br_3d is None else br_3d
                bphi_3d = np.zeros_like(rho_3d) if bphi_3d is None else bphi_3d
                bz_3d = np.zeros_like(rho_3d) if bz_3d is None else bz_3d

            if thetae_from_u_3d and u_3d is not None:
                electron_model = _electron_model_name(args.electron_model, not synthetic_b)
                if electron_model == "r-beta" and not synthetic_b:
                    thetae_3d, electron_stats = _thetae_from_rbeta_prescription(
                        u_3d,
                        rho_3d,
                        br_3d,
                        bphi_3d,
                        bz_3d,
                        args.u_to_thetae,
                        args.adiabatic_gamma,
                        args.electron_r_low,
                        args.electron_r_high,
                    )
                    thetae_prescription = {
                        "type": "r_beta_electron_temperature",
                        "description": (
                            "thetae = (u_to_thetae * u/rho) / (Ti/Te), "
                            "Ti/Te=(R_low + R_high*beta^2)/(1+beta^2), "
                            "beta=p_gas/(B^2/2) using imported primitive B as a code-unit proxy"
                        ),
                        "requestedModel": args.electron_model,
                        "resolvedModel": electron_model,
                        "rLow": float(args.electron_r_low),
                        "rHigh": float(args.electron_r_high),
                        "adiabaticGamma": float(args.adiabatic_gamma),
                        "stats": electron_stats,
                    }
                else:
                    thetae_prescription.update({
                        "requestedModel": args.electron_model,
                        "resolvedModel": electron_model,
                        "note": "single-temperature u/rho used because B fields are unavailable or model was requested",
                    })

            phi_filter_active = (
                abs(args.phi_contrast - 1.0) >= 1e-12
                or args.phi_residual_smooth > 0.0
                or args.rz_residual_smooth > 0.0
            )
            if phi_filter_active:
                rho_3d = _amplify_phi_deviation_positive(
                    rho_3d,
                    args.phi_contrast,
                    2,
                    1e-30,
                    args.phi_contrast_max_ratio,
                    args.phi_residual_smooth,
                    args.phi_residual_smooth_passes,
                    args.rz_residual_smooth,
                    args.rz_residual_smooth_passes,
                )
                thetae_3d = _amplify_phi_deviation_positive(
                    thetae_3d,
                    args.phi_contrast,
                    2,
                    1e-8,
                    args.phi_contrast_max_ratio,
                    args.phi_residual_smooth,
                    args.phi_residual_smooth_passes,
                    args.rz_residual_smooth,
                    args.rz_residual_smooth_passes,
                )
                if pressure_3d is not None:
                    pressure_3d = _amplify_phi_deviation_positive(
                        pressure_3d,
                        args.phi_contrast,
                        2,
                        0.0,
                        args.phi_contrast_max_ratio,
                        args.phi_residual_smooth,
                        args.phi_residual_smooth_passes,
                        args.rz_residual_smooth,
                        args.rz_residual_smooth_passes,
                    )
                if bsq_3d is not None:
                    bsq_3d = _amplify_phi_deviation_positive(
                        bsq_3d,
                        args.phi_contrast,
                        2,
                        0.0,
                        args.phi_contrast_max_ratio,
                        args.phi_residual_smooth,
                        args.phi_residual_smooth_passes,
                        args.rz_residual_smooth,
                        args.rz_residual_smooth_passes,
                    )
                if sigma_3d is not None:
                    sigma_3d = _amplify_phi_deviation_positive(
                        sigma_3d,
                        args.phi_contrast,
                        2,
                        0.0,
                        args.phi_contrast_max_ratio,
                        args.phi_residual_smooth,
                        args.phi_residual_smooth_passes,
                        args.rz_residual_smooth,
                        args.rz_residual_smooth_passes,
                    )
                vr_3d = _amplify_phi_deviation_linear(
                    vr_3d, args.phi_contrast, 2, 0.999, args.phi_residual_smooth,
                    args.phi_residual_smooth_passes, args.rz_residual_smooth,
                    args.rz_residual_smooth_passes
                )
                vphi_3d = _amplify_phi_deviation_linear(
                    vphi_3d, args.phi_contrast, 2, 0.999, args.phi_residual_smooth,
                    args.phi_residual_smooth_passes, args.rz_residual_smooth,
                    args.rz_residual_smooth_passes
                )
                vz_3d = _amplify_phi_deviation_linear(
                    vz_3d, args.phi_contrast, 2, 0.999, args.phi_residual_smooth,
                    args.phi_residual_smooth_passes, args.rz_residual_smooth,
                    args.rz_residual_smooth_passes
                )
                br_3d = _amplify_phi_deviation_linear(
                    br_3d, args.phi_contrast, 2, None, args.phi_residual_smooth,
                    args.phi_residual_smooth_passes, args.rz_residual_smooth,
                    args.rz_residual_smooth_passes
                )
                bphi_3d = _amplify_phi_deviation_linear(
                    bphi_3d, args.phi_contrast, 2, None, args.phi_residual_smooth,
                    args.phi_residual_smooth_passes, args.rz_residual_smooth,
                    args.rz_residual_smooth_passes
                )
                bz_3d = _amplify_phi_deviation_linear(
                    bz_3d, args.phi_contrast, 2, None, args.phi_residual_smooth,
                    args.phi_residual_smooth_passes, args.rz_residual_smooth,
                    args.rz_residual_smooth_passes
                )

            r_norm_src = np.asarray(r, dtype=np.float64) * args.r_to_rs
            src_r_min = float(np.nanmin(r_norm_src))
            src_r_max = float(np.nanmax(r_norm_src))
            r_min = src_r_min if args.r_min <= 0.0 else float(args.r_min)
            if args.r_max <= 0.0:
                bmag_3d = np.sqrt(br_3d * br_3d + bphi_3d * bphi_3d + bz_3d * bz_3d)
                r_max, radial_range = _emissive_auto_r_max(r_norm_src, rho_3d, thetae_3d, bmag_3d, source_format)
            else:
                r_max = float(args.r_max)
                radial_range = {"mode": "explicit", "sourceRMax": src_r_max, "selectedRMax": r_max}
            if not (r_max > r_min):
                raise ValueError(f"invalid radial range: r_min={r_min}, r_max={r_max}")
            r_dst = _warped_radial_grid(r_min, r_max, args.nr, args.r_warp)
            z_dst = np.linspace(-args.z_max, args.z_max, args.nz, dtype=np.float64)

            rho_dst = _sample_cube_to_rphiz(np.maximum(rho_3d, 1e-30), r_norm_src, theta, r_dst, z_dst, args.nphi)
            thetae_dst = _sample_cube_to_rphiz(np.maximum(thetae_3d, 1e-8), r_norm_src, theta, r_dst, z_dst, args.nphi)
            vr_dst = _sample_cube_to_rphiz(vr_3d, r_norm_src, theta, r_dst, z_dst, args.nphi)
            vphi_dst = _sample_cube_to_rphiz(vphi_3d, r_norm_src, theta, r_dst, z_dst, args.nphi)
            vz_dst = _sample_cube_to_rphiz(vz_3d, r_norm_src, theta, r_dst, z_dst, args.nphi)
            br_dst = _sample_cube_to_rphiz(br_3d, r_norm_src, theta, r_dst, z_dst, args.nphi)
            bphi_dst = _sample_cube_to_rphiz(bphi_3d, r_norm_src, theta, r_dst, z_dst, args.nphi)
            bz_dst = _sample_cube_to_rphiz(bz_3d, r_norm_src, theta, r_dst, z_dst, args.nphi)

            if pressure_3d is not None:
                pressure_dst = _sample_cube_to_rphiz(np.maximum(pressure_3d, 0.0), r_norm_src, theta, r_dst, z_dst, args.nphi)
                sidecar_stats["pressure"] = _finite_stats(pressure_dst)
                consistency_stats["thetae_vs_pressure_over_rho"] = _finite_stats(
                    thetae_dst / np.maximum(pressure_dst / np.maximum(rho_dst, 1e-30), 1e-30)
                )
            if bsq_3d is not None:
                sidecar_stats["bsq"] = _finite_stats(_sample_cube_to_rphiz(np.maximum(bsq_3d, 0.0), r_norm_src, theta, r_dst, z_dst, args.nphi))
            if sigma_3d is not None:
                sidecar_stats["sigma"] = _finite_stats(_sample_cube_to_rphiz(np.maximum(sigma_3d, 0.0), r_norm_src, theta, r_dst, z_dst, args.nphi))

            vol0 = np.zeros((args.nz, args.nphi, args.nr, 4), dtype=np.float32)
            vol1 = np.zeros((args.nz, args.nphi, args.nr, 4), dtype=np.float32)
            vol0[:, :, :, 0] = np.log(np.maximum(rho_dst, 1e-30)).astype(np.float32)
            vol0[:, :, :, 1] = np.log(np.maximum(thetae_dst, 1e-8)).astype(np.float32)
            vol0[:, :, :, 2] = np.clip(vr_dst, -0.999, 0.999).astype(np.float32)
            vol0[:, :, :, 3] = np.clip(vphi_dst, -0.999, 0.999).astype(np.float32)
            vol1[:, :, :, 0] = np.clip(vz_dst, -0.999, 0.999).astype(np.float32)
            vol1[:, :, :, 1] = br_dst.astype(np.float32)
            vol1[:, :, :, 2] = bphi_dst.astype(np.float32)
            vol1[:, :, :, 3] = bz_dst.astype(np.float32)

        else:
            rho_2d = _extract_rphi_plane(np.asarray(ds_map[rho_key]), nr_src, nphi_src, args.theta_index, args.theta_average, "rho")

            thetae_key, thetae_2d = _load_optional_plane(
                ds_map,
                args.thetae_key,
                ["thetae", "theta_e", "Thetae", "Theta", "Te", "electron_temp", "temp_e"],
                nr_src,
                nphi_src,
                args.theta_index,
                args.theta_average,
                "thetae",
            )
            u_key, u_2d = _load_optional_plane(
                ds_map,
                args.u_key,
                ["u", "uu", "internal_energy", "eps", "prs", "press", "pressure"],
                nr_src,
                nphi_src,
                args.theta_index,
                args.theta_average,
                "u",
            )
            thetae_from_u_2d = thetae_2d is None and u_2d is not None
            if thetae_2d is None:
                if u_2d is None:
                    thetae_2d = np.full((nr_src, nphi_src), 0.08, dtype=np.float64)
                    thetae_prescription = {
                        "type": "constant_floor",
                        "description": "thetae fallback constant 0.08",
                    }
                else:
                    thetae_2d = _thetae_from_energy_density(u_2d, rho_2d, args.u_to_thetae)
                    thetae_prescription = {
                        "type": "u_over_rho",
                        "description": "thetae = u_to_thetae * max(u, floor) / max(rho, floor)",
                    }
            else:
                thetae_prescription = {
                    "type": "dataset",
                    "description": "thetae dataset used directly",
                }

            pressure_key, pressure_2d = _load_optional_plane(
                ds_map,
                args.pressure_key,
                ["p", "press", "pressure", "prs"],
                nr_src,
                nphi_src,
                args.theta_index,
                args.theta_average,
                "pressure",
            )
            bsq_key, bsq_2d = _load_optional_plane(
                ds_map,
                args.bsq_key,
                ["bsq", "b2", "b_squared", "magnetic_pressure_2"],
                nr_src,
                nphi_src,
                args.theta_index,
                args.theta_average,
                "bsq",
            )
            sigma_key, sigma_2d = _load_optional_plane(
                ds_map,
                args.sigma_key,
                ["sigma", "magnetization"],
                nr_src,
                nphi_src,
                args.theta_index,
                args.theta_average,
                "sigma",
            )

            u0_key, u0_2d = _load_optional_plane(
                ds_map,
                args.u0_key,
                ["u0", "ut", "u_t", "ucon0"],
                nr_src,
                nphi_src,
                args.theta_index,
                args.theta_average,
                "u0",
            )

            vr_key, vr_2d = _load_optional_plane(
                ds_map,
                args.vr_key,
                ["vr", "v_r", "vx1", "u1", "v1", "vel1"],
                nr_src,
                nphi_src,
                args.theta_index,
                args.theta_average,
                "v_r",
            )
            vphi_key, vphi_2d = _load_optional_plane(
                ds_map,
                args.vphi_key,
                ["vphi", "v_phi", "vx3", "u3", "v3", "vel3"],
                nr_src,
                nphi_src,
                args.theta_index,
                args.theta_average,
                "v_phi",
            )
            vz_key, vz_2d = _load_optional_plane(
                ds_map,
                args.vz_key,
                ["vz", "v_z", "vx2", "u2", "v2", "vel2"],
                nr_src,
                nphi_src,
                args.theta_index,
                args.theta_average,
                "v_z",
            )
            br_key, br_2d = _load_optional_plane(
                ds_map,
                args.br_key,
                ["Br", "B_r", "B1", "bx1", "b1"],
                nr_src,
                nphi_src,
                args.theta_index,
                args.theta_average,
                "B_r",
            )
            bphi_key, bphi_2d = _load_optional_plane(
                ds_map,
                args.bphi_key,
                ["Bphi", "B_phi", "B3", "bx3", "b3"],
                nr_src,
                nphi_src,
                args.theta_index,
                args.theta_average,
                "B_phi",
            )
            bz_key, bz_2d = _load_optional_plane(
                ds_map,
                args.bz_key,
                ["Bz", "B_z", "B2", "bx2", "b2"],
                nr_src,
                nphi_src,
                args.theta_index,
                args.theta_average,
                "B_z",
            )

            vr_2d = np.zeros_like(rho_2d) if vr_2d is None else vr_2d
            vphi_2d = np.zeros_like(rho_2d) if vphi_2d is None else vphi_2d
            vz_2d = np.zeros_like(rho_2d) if vz_2d is None else vz_2d
            vr_2d, velocity_modes["vr"] = _velocity_to_beta(vr_2d, u0_2d, vr_key, args.velocity_mode, "v_r")
            vphi_2d, velocity_modes["vphi"] = _velocity_to_beta(vphi_2d, u0_2d, vphi_key, args.velocity_mode, "v_phi")
            vz_2d, velocity_modes["vz"] = _velocity_to_beta(vz_2d, u0_2d, vz_key, args.velocity_mode, "v_z")
            if br_2d is None and bphi_2d is None and bz_2d is None:
                if not args.allow_synthetic_b:
                    raise ValueError(
                        "magnetic datasets are missing (Br/Bphi/Bz). "
                        "Provide physically consistent B fields, or pass --allow-synthetic-b explicitly."
                    )
                synthetic_b = True
                b_eq = np.sqrt(np.maximum(np.maximum(rho_2d, 1e-30) * np.maximum(thetae_2d, 1e-8), 1e-20))
                br_2d = 0.02 * b_eq
                bphi_2d = 0.35 * b_eq
                bz_2d = 0.06 * b_eq
            else:
                br_2d = np.zeros_like(rho_2d) if br_2d is None else br_2d
                bphi_2d = np.zeros_like(rho_2d) if bphi_2d is None else bphi_2d
                bz_2d = np.zeros_like(rho_2d) if bz_2d is None else bz_2d

            if thetae_from_u_2d and u_2d is not None:
                electron_model = _electron_model_name(args.electron_model, not synthetic_b)
                if electron_model == "r-beta" and not synthetic_b:
                    thetae_2d, electron_stats = _thetae_from_rbeta_prescription(
                        u_2d,
                        rho_2d,
                        br_2d,
                        bphi_2d,
                        bz_2d,
                        args.u_to_thetae,
                        args.adiabatic_gamma,
                        args.electron_r_low,
                        args.electron_r_high,
                    )
                    thetae_prescription = {
                        "type": "r_beta_electron_temperature",
                        "description": (
                            "thetae = (u_to_thetae * u/rho) / (Ti/Te), "
                            "Ti/Te=(R_low + R_high*beta^2)/(1+beta^2), "
                            "beta=p_gas/(B^2/2) using imported primitive B as a code-unit proxy"
                        ),
                        "requestedModel": args.electron_model,
                        "resolvedModel": electron_model,
                        "rLow": float(args.electron_r_low),
                        "rHigh": float(args.electron_r_high),
                        "adiabaticGamma": float(args.adiabatic_gamma),
                        "stats": electron_stats,
                    }
                else:
                    thetae_prescription.update({
                        "requestedModel": args.electron_model,
                        "resolvedModel": electron_model,
                        "note": "single-temperature u/rho used because B fields are unavailable or model was requested",
                    })

            phi_filter_active = (
                abs(args.phi_contrast - 1.0) >= 1e-12
                or args.phi_residual_smooth > 0.0
                or args.rz_residual_smooth > 0.0
            )
            if phi_filter_active:
                rho_2d = _amplify_phi_deviation_positive(
                    rho_2d,
                    args.phi_contrast,
                    1,
                    1e-30,
                    args.phi_contrast_max_ratio,
                    args.phi_residual_smooth,
                    args.phi_residual_smooth_passes,
                    args.rz_residual_smooth,
                    args.rz_residual_smooth_passes,
                )
                thetae_2d = _amplify_phi_deviation_positive(
                    thetae_2d,
                    args.phi_contrast,
                    1,
                    1e-8,
                    args.phi_contrast_max_ratio,
                    args.phi_residual_smooth,
                    args.phi_residual_smooth_passes,
                    args.rz_residual_smooth,
                    args.rz_residual_smooth_passes,
                )
                if pressure_2d is not None:
                    pressure_2d = _amplify_phi_deviation_positive(
                        pressure_2d,
                        args.phi_contrast,
                        1,
                        0.0,
                        args.phi_contrast_max_ratio,
                        args.phi_residual_smooth,
                        args.phi_residual_smooth_passes,
                        args.rz_residual_smooth,
                        args.rz_residual_smooth_passes,
                    )
                if bsq_2d is not None:
                    bsq_2d = _amplify_phi_deviation_positive(
                        bsq_2d,
                        args.phi_contrast,
                        1,
                        0.0,
                        args.phi_contrast_max_ratio,
                        args.phi_residual_smooth,
                        args.phi_residual_smooth_passes,
                        args.rz_residual_smooth,
                        args.rz_residual_smooth_passes,
                    )
                if sigma_2d is not None:
                    sigma_2d = _amplify_phi_deviation_positive(
                        sigma_2d,
                        args.phi_contrast,
                        1,
                        0.0,
                        args.phi_contrast_max_ratio,
                        args.phi_residual_smooth,
                        args.phi_residual_smooth_passes,
                        args.rz_residual_smooth,
                        args.rz_residual_smooth_passes,
                    )
                vr_2d = _amplify_phi_deviation_linear(
                    vr_2d, args.phi_contrast, 1, 0.999, args.phi_residual_smooth,
                    args.phi_residual_smooth_passes, args.rz_residual_smooth,
                    args.rz_residual_smooth_passes
                )
                vphi_2d = _amplify_phi_deviation_linear(
                    vphi_2d, args.phi_contrast, 1, 0.999, args.phi_residual_smooth,
                    args.phi_residual_smooth_passes, args.rz_residual_smooth,
                    args.rz_residual_smooth_passes
                )
                vz_2d = _amplify_phi_deviation_linear(
                    vz_2d, args.phi_contrast, 1, 0.999, args.phi_residual_smooth,
                    args.phi_residual_smooth_passes, args.rz_residual_smooth,
                    args.rz_residual_smooth_passes
                )
                br_2d = _amplify_phi_deviation_linear(
                    br_2d, args.phi_contrast, 1, None, args.phi_residual_smooth,
                    args.phi_residual_smooth_passes, args.rz_residual_smooth,
                    args.rz_residual_smooth_passes
                )
                bphi_2d = _amplify_phi_deviation_linear(
                    bphi_2d, args.phi_contrast, 1, None, args.phi_residual_smooth,
                    args.phi_residual_smooth_passes, args.rz_residual_smooth,
                    args.rz_residual_smooth_passes
                )
                bz_2d = _amplify_phi_deviation_linear(
                    bz_2d, args.phi_contrast, 1, None, args.phi_residual_smooth,
                    args.phi_residual_smooth_passes, args.rz_residual_smooth,
                    args.rz_residual_smooth_passes
                )

            r_norm_src = np.asarray(r, dtype=np.float64) * args.r_to_rs
            src_r_min = float(np.nanmin(r_norm_src))
            src_r_max = float(np.nanmax(r_norm_src))
            r_min = src_r_min if args.r_min <= 0.0 else float(args.r_min)
            if args.r_max <= 0.0:
                bmag_2d = np.sqrt(br_2d * br_2d + bphi_2d * bphi_2d + bz_2d * bz_2d)
                r_max, radial_range = _emissive_auto_r_max(r_norm_src, rho_2d, thetae_2d, bmag_2d, source_format)
            else:
                r_max = float(args.r_max)
                radial_range = {"mode": "explicit", "sourceRMax": src_r_max, "selectedRMax": r_max}
            if not (r_max > r_min):
                raise ValueError(f"invalid radial range: r_min={r_min}, r_max={r_max}")

            r_dst = _warped_radial_grid(r_min, r_max, args.nr, args.r_warp)
            rho_dst = _resample_rphi(np.maximum(rho_2d, 1e-30), r_norm_src, r_dst, args.nphi)
            thetae_dst = _resample_rphi(np.maximum(thetae_2d, 1e-8), r_norm_src, r_dst, args.nphi)
            vr_dst = _resample_rphi(vr_2d, r_norm_src, r_dst, args.nphi)
            vphi_dst = _resample_rphi(vphi_2d, r_norm_src, r_dst, args.nphi)
            vz_dst = _resample_rphi(vz_2d, r_norm_src, r_dst, args.nphi)
            br_dst = _resample_rphi(br_2d, r_norm_src, r_dst, args.nphi)
            bphi_dst = _resample_rphi(bphi_2d, r_norm_src, r_dst, args.nphi)
            bz_dst = _resample_rphi(bz_2d, r_norm_src, r_dst, args.nphi)

            if pressure_2d is not None:
                pressure_dst = _resample_rphi(np.maximum(pressure_2d, 0.0), r_norm_src, r_dst, args.nphi)
                sidecar_stats["pressure"] = _finite_stats(pressure_dst)
                consistency_stats["thetae_vs_pressure_over_rho"] = _finite_stats(
                    thetae_dst / np.maximum(pressure_dst / np.maximum(rho_dst, 1e-30), 1e-30)
                )
            if bsq_2d is not None:
                sidecar_stats["bsq"] = _finite_stats(_resample_rphi(np.maximum(bsq_2d, 0.0), r_norm_src, r_dst, args.nphi))
            if sigma_2d is not None:
                sidecar_stats["sigma"] = _finite_stats(_resample_rphi(np.maximum(sigma_2d, 0.0), r_norm_src, r_dst, args.nphi))

            z = np.linspace(-args.z_max, args.z_max, args.nz, dtype=np.float64)
            z01 = np.clip(np.abs(z) / max(args.z_max, 1e-12), 0.0, 1.0)
            dens_scale = np.exp(-np.power(z01 / max(args.vertical_density_scale, 1e-3), 2.0))
            thetae_scale = 1.0 - np.clip(args.vertical_thetae_drop, 0.0, 0.95) * np.power(z01, 1.15)
            vphi_scale = 1.0 - np.clip(args.vertical_vphi_drop, 0.0, 0.95) * np.power(z01, 1.3)
            vel_scale = np.exp(-np.power(z01 / max(args.vertical_vel_scale, 1e-3), 2.0))
            b_scale = np.exp(-np.power(z01 / max(args.vertical_b_scale, 1e-3), 2.0))

            thetae_scale = np.clip(thetae_scale, 0.05, 4.0)
            vphi_scale = np.clip(vphi_scale, 0.05, 4.0)
            vel_scale = np.clip(vel_scale, 0.0, 1.0)
            b_scale = np.clip(b_scale, 0.0, 1.0)

            vol0 = np.zeros((args.nz, args.nphi, args.nr, 4), dtype=np.float32)
            vol1 = np.zeros((args.nz, args.nphi, args.nr, 4), dtype=np.float32)
            for k, z_val in enumerate(z):
                rho_k = np.maximum(rho_dst * dens_scale[k], 1e-30)
                thetae_k = np.maximum(thetae_dst * thetae_scale[k], 1e-8)
                vr_k = vr_dst * vel_scale[k]
                vphi_k = vphi_dst * vphi_scale[k]
                vz_k = vz_dst * vel_scale[k] + 0.02 * (z_val / max(args.z_max, 1e-9))
                br_k = br_dst * b_scale[k]
                bphi_k = bphi_dst * b_scale[k]
                bz_k = bz_dst * (0.88 + 0.12 * (1.0 - z01[k]))

                vol0[k, :, :, 0] = np.log(rho_k).T.astype(np.float32)
                vol0[k, :, :, 1] = np.log(thetae_k).T.astype(np.float32)
                vol0[k, :, :, 2] = np.clip(vr_k.T, -0.999, 0.999).astype(np.float32)
                vol0[k, :, :, 3] = np.clip(vphi_k.T, -0.999, 0.999).astype(np.float32)
                vol1[k, :, :, 0] = np.clip(vz_k.T, -0.999, 0.999).astype(np.float32)
                vol1[k, :, :, 1] = br_k.T.astype(np.float32)
                vol1[k, :, :, 2] = bphi_k.T.astype(np.float32)
                vol1[k, :, :, 3] = bz_k.T.astype(np.float32)

    vol0_path.parent.mkdir(parents=True, exist_ok=True)
    vol1_path.parent.mkdir(parents=True, exist_ok=True)
    meta_path.parent.mkdir(parents=True, exist_ok=True)

    vol0.tofile(vol0_path)
    vol1.tofile(vol1_path)

    keys = {
        "r": r_key,
        "theta": theta_key_used if theta_key_used is not None else "",
        "phi": phi_key,
        "rho": rho_key,
        "thetae": thetae_key if thetae_key is not None else "",
        "u": u_key if u_key is not None else "",
        "pressure": pressure_key if pressure_key is not None else "",
        "bsq": bsq_key if bsq_key is not None else "",
        "sigma": sigma_key if sigma_key is not None else "",
        "u0": u0_key if u0_key is not None else "",
        "vr": vr_key if vr_key is not None else "",
        "vphi": vphi_key if vphi_key is not None else "",
        "vz": vz_key if vz_key is not None else "",
        "br": br_key if br_key is not None else "",
        "bphi": bphi_key if bphi_key is not None else "",
        "bz": bz_key if bz_key is not None else "",
    }
    rho_stats_field = np.exp(np.clip(vol0[:, :, :, 0], -80.0, 80.0))
    thetae_stats_field = np.exp(np.clip(vol0[:, :, :, 1], -80.0, 80.0))
    beta_stats_field = np.sqrt(vol0[:, :, :, 2] ** 2 + vol0[:, :, :, 3] ** 2 + vol1[:, :, :, 0] ** 2)
    b_stats_field = np.sqrt(vol1[:, :, :, 1] ** 2 + vol1[:, :, :, 2] ** 2 + vol1[:, :, :, 3] ** 2)
    phi_variation_stats = {
        "rho": _phi_variation_stats(rho_stats_field),
        "thetae": _phi_variation_stats(thetae_stats_field),
        "betaMagnitude": _phi_variation_stats(beta_stats_field),
        "bMagnitude": _phi_variation_stats(b_stats_field),
    }
    r_dst_values = _warped_radial_grid(float(r_min), float(r_max), args.nr, args.r_warp)
    z_dst_values = np.linspace(-float(args.z_max), float(args.z_max), args.nz, dtype=np.float64)
    phi_variation_bands = {
        "rho": _phi_variation_band_stats(rho_stats_field, r_dst_values, z_dst_values),
        "thetae": _phi_variation_band_stats(thetae_stats_field, r_dst_values, z_dst_values),
        "betaMagnitude": _phi_variation_band_stats(beta_stats_field, r_dst_values, z_dst_values),
        "bMagnitude": _phi_variation_band_stats(b_stats_field, r_dst_values, z_dst_values),
    }
    suitability = _snapshot_suitability(phi_variation_stats, bool(synthetic_b), bool(use_native_3d))

    meta = {
        "format": "grmhd_dual_float4_v1",
        "r": args.nr,
        "phi": args.nphi,
        "z": args.nz,
        "rNormMin": float(r_min),
        "rNormMax": float(r_max),
        "rNormWarp": float(max(args.r_warp, 1e-6)),
        "radialRange": radial_range,
        "zNormMax": float(args.z_max),
        "vol0": str(vol0_path),
        "vol1": str(vol1_path),
        "vol0Channels": ["log_rho", "log_thetae", "v_r", "v_phi"],
        "vol1Channels": ["v_z", "B_r", "B_phi", "B_z"],
        "source": str(in_path),
        "rToRs": float(args.r_to_rs),
        "thetaIndex": int(args.theta_index),
        "thetaAverage": bool(args.theta_average),
        "uToThetae": float(args.u_to_thetae),
        "keys": keys,
        "sourceFormat": source_format,
        "sourceAttributes": source_attrs,
        "thetaePrescription": thetae_prescription,
        "velocity": {
            "requestedMode": args.velocity_mode,
            "componentModes": velocity_modes,
            "storedChannels": "dimensionless beta-like components clipped to [-0.999,0.999]",
            "fourVelocityConversion": "u^i/u^0 coordinate 3-velocity approximation when selected",
        },
        "phiContrast": {
            "factor": float(args.phi_contrast),
            "maxPositiveRatio": float(args.phi_contrast_max_ratio),
            "residualSmooth": float(args.phi_residual_smooth),
            "residualSmoothPasses": int(args.phi_residual_smooth_passes),
            "rzResidualSmooth": float(args.rz_residual_smooth),
            "rzResidualSmoothPasses": int(args.rz_residual_smooth_passes),
            "description": (
                "diagnostic amplification of existing azimuthal deviations around each r-z phi mean; "
                "factor=1 preserves the imported source data unless residual smoothing is enabled; "
                "residualSmooth low-passes the zero-mean phi residual, and rzResidualSmooth low-passes "
                "non-periodic r/z residuals while preserving phi-ring means"
            ),
        },
        "stats": {
            "rho": _finite_stats(rho_stats_field),
            "thetae": _finite_stats(thetae_stats_field),
            "betaMagnitude": _finite_stats(beta_stats_field),
            "bMagnitude": _finite_stats(b_stats_field),
            "phiVariation": phi_variation_stats,
            "phiVariationBands": phi_variation_bands,
            "sidecar": sidecar_stats,
            "consistency": consistency_stats,
        },
        "suitability": suitability,
        "syntheticB": bool(synthetic_b),
        "native3D": bool(use_native_3d),
        "native3DMode": args.native_3d,
        "native3DReason": native_3d_reason,
    }
    if use_native_3d:
        meta["mapping"] = {
            "type": "native_r_theta_phi_to_r_phi_z",
            "zToTheta": "theta = arccos(clamp(z/r,-1,1))",
        }
    else:
        meta["verticalProfile"] = {
            "densityScale": float(args.vertical_density_scale),
            "thetaeDrop": float(args.vertical_thetae_drop),
            "vphiDrop": float(args.vertical_vphi_drop),
            "velScale": float(args.vertical_vel_scale),
            "bScale": float(args.vertical_b_scale),
        }
    with meta_path.open("w", encoding="utf-8") as f:
        json.dump(meta, f, ensure_ascii=True, indent=2, sort_keys=True)

    print(f"saved vol0: {vol0_path}")
    print(f"saved vol1: {vol1_path}")
    print(f"saved meta: {meta_path}")
    print(f"grid: {args.nr}x{args.nphi}x{args.nz}, rNorm=[{r_min:.4f}, {r_max:.4f}], zNormMax={args.z_max:.4f}")
    if radial_range:
        mode = radial_range.get("mode", "unknown")
        src = float(radial_range.get("sourceRMax", r_max))
        sel = float(radial_range.get("selectedRMax", r_max))
        print(f"radial range: {mode}, sourceRMax={src:.4f}, selectedRMax={sel:.4f}")
    if use_native_3d:
        print("mapping: native 3D r-theta-phi -> r-phi-z (theta from z/r)")
    elif native_3d_reason:
        print(f"mapping: fallback 2D profile ({native_3d_reason})")


if __name__ == "__main__":
    main()
