#!/usr/bin/env python3
"""Audit whether a GRMHD HDF5 snapshot can support visible flow structure.

This script intentionally does not normalize or beautify the data. It reports
whether the available rho/thetae/B/velocity fields contain enough azimuthal and
dynamic variation to justify expecting turbulent visible structure in the
renderer.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Dict, List, Optional, Tuple

import h5py
import numpy as np


def _dataset_map(h5: h5py.File) -> Dict[str, object]:
    out: Dict[str, object] = {}

    def visit(name: str, obj: object) -> None:
        if isinstance(obj, h5py.Dataset):
            out[name] = obj
            out[name.split("/")[-1]] = obj

    h5.visititems(visit)
    return out


def _resolve(ds: Dict[str, object], candidates: list[str]) -> Tuple[str, Optional[np.ndarray]]:
    for key in candidates:
        if key in ds:
            return key, np.asarray(ds[key])
    return "", None


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


def _h5_value(h5: h5py.File, key: str, default: object = None) -> object:
    if key not in h5:
        return default
    return _decode_scalar(h5[key][()])


def _h5_float(h5: h5py.File, key: str, default: float) -> float:
    value = _h5_value(h5, key, default)
    try:
        return float(value)
    except Exception:
        return float(default)


def _fmks_theta_from_native_x2(h5: h5py.File, x1: np.ndarray, x2: np.ndarray) -> np.ndarray:
    """Approximate FMKS native x2 -> Kerr-Schild theta using pyharm's public formula."""
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


def _inject_primitive_dump(h5: h5py.File, ds: Dict[str, object]) -> Dict[str, object]:
    if "prims" not in ds or "header/prim_names" not in ds:
        return {"type": "explicit_datasets"}
    prims = np.asarray(ds["prims"])
    if prims.ndim != 4:
        return {"type": "explicit_datasets", "primitiveRejected": f"prims has shape {prims.shape}"}
    names_raw = np.asarray(ds["header/prim_names"])
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

    ds.setdefault("r", r)
    ds.setdefault("theta", theta)
    ds.setdefault("phi", phi)
    ds.setdefault("rho", prims[:, :, :, index["RHO"]])
    ds.setdefault("uu", prims[:, :, :, index["UU"]])
    ds.setdefault("vx1", prims[:, :, :, index["U1"]])
    ds.setdefault("vx2", prims[:, :, :, index["U2"]])
    ds.setdefault("vx3", prims[:, :, :, index["U3"]])
    ds.setdefault("B1", prims[:, :, :, index["B1"]])
    ds.setdefault("B2", prims[:, :, :, index["B2"]])
    ds.setdefault("B3", prims[:, :, :, index["B3"]])
    return {
        "type": "primitive_prims",
        "layout": "KHARMA/IHARM prims[n1,n2,n3,nprim]",
        "coordinates": coordinates,
        "primitiveNames": names,
        "velocityInterpretation": "U1/U2/U3 treated as beta-like proxies for this data-quality audit",
        "coordinateMapping": "r=exp(x1); theta=MKS/FMKS native map; phi=x3",
        "shape": [int(n1), int(n2), int(n3)],
    }


def _finite_stats(x: np.ndarray) -> Dict[str, float]:
    arr = np.asarray(x, dtype=np.float64)
    arr = arr[np.isfinite(arr)]
    if arr.size == 0:
        return {}
    return {
        "min": float(np.min(arr)),
        "p01": float(np.percentile(arr, 1.0)),
        "p50": float(np.percentile(arr, 50.0)),
        "p95": float(np.percentile(arr, 95.0)),
        "p99": float(np.percentile(arr, 99.0)),
        "max": float(np.max(arr)),
        "mean": float(np.mean(arr)),
    }


def _as_r_theta_phi(name: str, arr: np.ndarray, nr: int, nth: int, nphi: int) -> np.ndarray:
    x = np.asarray(arr)
    if x.shape == (nr, nth, nphi):
        return x.astype(np.float64)
    if x.shape == (nr, nphi, nth):
        return np.transpose(x, (0, 2, 1)).astype(np.float64)
    if x.shape == (nth, nr, nphi):
        return np.transpose(x, (1, 0, 2)).astype(np.float64)
    if x.shape == (nphi, nr, nth):
        return np.transpose(x, (1, 2, 0)).astype(np.float64)
    if x.ndim == 3:
        axes = list(range(3))
        r_axes = [i for i, s in enumerate(x.shape) if s == nr]
        th_axes = [i for i, s in enumerate(x.shape) if s == nth]
        ph_axes = [i for i, s in enumerate(x.shape) if s == nphi]
        if r_axes and th_axes and ph_axes:
            axes_out = [r_axes[0], th_axes[0], ph_axes[0]]
            return np.transpose(x, axes_out).astype(np.float64)
    raise ValueError(f"{name}: cannot infer (r,theta,phi) axes from shape {x.shape}")


def _phi_stats(field: np.ndarray, r: np.ndarray, theta: np.ndarray) -> Dict[str, object]:
    safe = np.where(np.isfinite(field), field, np.nan)
    mean_phi = np.nanmean(safe, axis=2)
    std_phi = np.nanstd(safe, axis=2)
    rel = std_phi / np.maximum(np.abs(mean_phi), 1e-30)
    rel = np.where(np.isfinite(rel), rel, np.nan)
    vals = rel[np.isfinite(rel)]
    global_stats = {
        "medianRelStd": float(np.percentile(vals, 50.0)) if vals.size else 0.0,
        "p95RelStd": float(np.percentile(vals, 95.0)) if vals.size else 0.0,
        "p99RelStd": float(np.percentile(vals, 99.0)) if vals.size else 0.0,
        "maxRelStd": float(np.max(vals)) if vals.size else 0.0,
    }
    bands = []
    r_min = float(np.nanmin(r))
    r_max = float(np.nanmax(r))
    theta_bands = [
        ("midplane_pm10deg", np.abs(theta - np.pi / 2.0) <= np.deg2rad(10.0)),
        ("midplane_pm20deg", np.abs(theta - np.pi / 2.0) <= np.deg2rad(20.0)),
        ("all_theta", np.ones(theta.shape, dtype=bool)),
    ]
    for r0, r1 in [(0.0, 0.25), (0.25, 0.50), (0.50, 0.75), (0.75, 1.0)]:
        lo = r_min + (r_max - r_min) * r0
        hi = r_min + (r_max - r_min) * r1
        r_mask = (r >= lo) & (r <= hi)
        for label, t_mask in theta_bands:
            v = rel[np.ix_(r_mask, t_mask)]
            v = v[np.isfinite(v)]
            if v.size == 0:
                continue
            bands.append(
                {
                    "rFrac": [r0, r1],
                    "rRange": [lo, hi],
                    "thetaBand": label,
                    "medianRelStd": float(np.percentile(v, 50.0)),
                    "p95RelStd": float(np.percentile(v, 95.0)),
                    "maxRelStd": float(np.max(v)),
                    "cells": int(v.size),
                }
            )
    profile = np.nanmean(safe, axis=(0, 1))
    global_stats["profileRelStd"] = float(np.nanstd(profile) / max(abs(np.nanmean(profile)), 1e-30))
    return {"global": global_stats, "bands": bands}


def _quality(phi: Dict[str, object], synthetic_b: bool) -> Dict[str, object]:
    def p95(name: str) -> float:
        item = phi.get(name, {})
        if not isinstance(item, dict):
            return 0.0
        glob = item.get("global", {})
        return float(glob.get("p95RelStd", 0.0)) if isinstance(glob, dict) else 0.0

    flow = max(p95("rho"), p95("thetae"))
    dynamics = max(p95("Bmag"), p95("betaMagnitude"))
    warnings = []
    if flow < 0.02:
        warnings.append("rho/thetae phi variation is too weak for rich visible turbulence")
    if dynamics < 0.01:
        warnings.append("B/velocity phi variation is too weak for visible dynamical flow texture")
    if synthetic_b:
        warnings.append("magnetic field appears unavailable or synthetic")
    if flow >= 0.08 and dynamics >= 0.03 and not synthetic_b:
        rating = "good"
    elif flow >= 0.02 or dynamics >= 0.01:
        rating = "limited"
    else:
        rating = "poor"
    return {
        "rating": rating,
        "flowPhiP95": flow,
        "dynamicsPhiP95": dynamics,
        "warnings": warnings,
    }


def audit(path: Path) -> Dict[str, object]:
    with h5py.File(path, "r") as h5:
        ds = _dataset_map(h5)
        source_format = _inject_primitive_dump(h5, ds)
        r_key, r = _resolve(ds, ["r", "x1v", "x1"])
        theta_key, theta = _resolve(ds, ["theta", "x2v", "x2"])
        phi_key, phi = _resolve(ds, ["phi", "x3v", "x3"])
        if r is None or theta is None or phi is None:
            raise ValueError("snapshot needs r/theta/phi coordinate datasets")
        r = np.asarray(r, dtype=np.float64).reshape(-1)
        theta = np.asarray(theta, dtype=np.float64).reshape(-1)
        phi = np.asarray(phi, dtype=np.float64).reshape(-1)
        nr, nth, nphi = int(r.size), int(theta.size), int(phi.size)

        rho_key, rho_raw = _resolve(ds, ["rho", "density"])
        thetae_key, thetae_raw = _resolve(ds, ["thetae"])
        u_key, u_raw = _resolve(ds, ["u", "uu", "internal_energy", "eps", "prs", "press", "pressure"])
        br_key, br_raw = _resolve(ds, ["Br", "B1", "b1", "B_r"])
        bphi_key, bphi_raw = _resolve(ds, ["Bphi", "B3", "b3", "B_phi"])
        bz_key, bz_raw = _resolve(ds, ["Bz", "B2", "b2", "B_z"])
        vr_key, vr_raw = _resolve(ds, ["vr", "vx1", "u1"])
        vphi_key, vphi_raw = _resolve(ds, ["vphi", "vx3", "u3"])
        vz_key, vz_raw = _resolve(ds, ["vz", "vx2", "u2"])
        u0_key, u0_raw = _resolve(ds, ["u0"])
        if rho_raw is None:
            raise ValueError("snapshot needs rho/density")
        rho = _as_r_theta_phi(rho_key, rho_raw, nr, nth, nphi)
        fields: Dict[str, np.ndarray] = {"rho": rho}
        keys: Dict[str, str] = {"rho": rho_key, "r": r_key, "theta": theta_key, "phi": phi_key}
        if thetae_raw is not None:
            fields["thetae"] = _as_r_theta_phi(thetae_key, thetae_raw, nr, nth, nphi)
            keys["thetae"] = thetae_key
        elif u_raw is not None:
            u = _as_r_theta_phi(u_key, u_raw, nr, nth, nphi)
            fields["thetae"] = np.maximum(u, 1e-30) / np.maximum(rho, 1e-30)
            keys["thetae"] = f"{u_key}/rho"
        synthetic_b = br_raw is None or bphi_raw is None or bz_raw is None
        if not synthetic_b:
            br = _as_r_theta_phi(br_key, br_raw, nr, nth, nphi)
            bp = _as_r_theta_phi(bphi_key, bphi_raw, nr, nth, nphi)
            bz = _as_r_theta_phi(bz_key, bz_raw, nr, nth, nphi)
            fields["Bmag"] = np.sqrt(br * br + bp * bp + bz * bz)
            keys["Bmag"] = ",".join([br_key, bphi_key, bz_key])
        if vr_raw is not None and vphi_raw is not None and vz_raw is not None:
            vr = _as_r_theta_phi(vr_key, vr_raw, nr, nth, nphi)
            vp = _as_r_theta_phi(vphi_key, vphi_raw, nr, nth, nphi)
            vz = _as_r_theta_phi(vz_key, vz_raw, nr, nth, nphi)
            if u0_raw is not None and any(k.startswith("u") for k in [vr_key, vphi_key, vz_key]):
                u0 = np.maximum(np.abs(_as_r_theta_phi(u0_key, u0_raw, nr, nth, nphi)), 1e-30)
                beta = np.sqrt((vr / u0) ** 2 + (vp / u0) ** 2 + (vz / u0) ** 2)
            else:
                beta = np.sqrt(vr * vr + vp * vp + vz * vz)
            fields["betaMagnitude"] = np.clip(beta, 0.0, 0.999)
            keys["betaMagnitude"] = ",".join([vr_key, vphi_key, vz_key])

        phi_stats = {name: _phi_stats(value, r, theta) for name, value in fields.items()}
        value_stats = {name: _finite_stats(value) for name, value in fields.items()}
        quality = _quality(phi_stats, synthetic_b)
        return {
            "path": str(path),
            "shape": [nr, nth, nphi],
            "keys": keys,
            "sourceFormat": source_format,
            "attrs": {str(k): (v.item() if hasattr(v, "item") else str(v)) for k, v in h5.attrs.items()},
            "valueStats": value_stats,
            "phiVariation": phi_stats,
            "quality": quality,
        }


def _paths_from_manifest(path: Path) -> List[Path]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    entries = payload.get("entries", [])
    if not isinstance(entries, list):
        raise ValueError(f"{path}: manifest entries must be a list")
    out: List[Path] = []
    for entry in entries:
        if not isinstance(entry, dict) or not entry.get("localPath"):
            raise ValueError(f"{path}: malformed manifest entry {entry!r}")
        out.append(Path(str(entry["localPath"])))
    return out


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("snapshot", nargs="*", help="HDF5 snapshot path(s)")
    parser.add_argument("--manifest", action="append", default=[], help="sequence manifest JSON from fetch_illinois_grmhd_snapshot.py")
    parser.add_argument("--json-out", default="", help="optional JSON output path")
    args = parser.parse_args()

    paths = [Path(p) for p in args.snapshot]
    for manifest in args.manifest:
        paths.extend(_paths_from_manifest(Path(manifest)))
    if not paths:
        raise SystemExit("provide at least one snapshot path or --manifest")

    results = [audit(path) for path in paths]
    text = json.dumps(results, indent=2, sort_keys=True)
    if args.json_out:
        Path(args.json_out).write_text(text + "\n", encoding="utf-8")
    print(text)
    for item in results:
        q = item["quality"]
        print(
            f"{item['path']}: rating={q['rating']} "
            f"flowPhiP95={q['flowPhiP95']:.4g} dynamicsPhiP95={q['dynamicsPhiP95']:.4g}"
        )
        for warning in q["warnings"]:
            print(f"  warn: {warning}")


if __name__ == "__main__":
    main()
