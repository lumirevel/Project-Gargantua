#!/usr/bin/env python3
import argparse
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
    required: bool,
) -> str:
    if explicit:
        m = _matches(ds_map, explicit)
        if len(m) == 1:
            return m[0]
        if len(m) > 1:
            raise ValueError(f"ambiguous {label} key '{explicit}': matches={m}")
        if required:
            raise KeyError(f"{label} key '{explicit}' not found")
        return ""

    for cand in candidates:
        m = _matches(ds_map, cand)
        if len(m) == 1:
            return m[0]
        if len(m) > 1:
            return sorted(m, key=len)[0]

    if required:
        tried = ", ".join(candidates)
        raise KeyError(f"failed to auto-detect {label}; tried: {tried}")
    return ""


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


def _find_rphi_axes(shape: Tuple[int, ...], nr: int, nphi: int, name: str) -> Tuple[int, int]:
    r_axes = [i for i, s in enumerate(shape) if s == nr]
    p_axes = [i for i, s in enumerate(shape) if s == nphi]
    if not r_axes or not p_axes:
        raise ValueError(f"{name}: cannot find r/phi axes for nr={nr}, nphi={nphi}, shape={shape}")
    for ra in r_axes:
        for pa in p_axes:
            if ra != pa:
                return ra, pa
    raise ValueError(f"{name}: ambiguous r/phi axis mapping for shape={shape}")


def _make_correlated_field(nr: int, nphi: int, seed: int, scale_cells: float) -> np.ndarray:
    rng = np.random.default_rng(seed)
    white = rng.standard_normal((nr, nphi))
    spec = np.fft.rfft2(white)
    kr = np.fft.fftfreq(nr)[:, None] * float(nr)
    kp = np.fft.rfftfreq(nphi)[None, :] * float(nphi)
    k = np.sqrt(kr * kr + kp * kp)
    smooth_scale = max(float(scale_cells), 1.0)
    k_cut = max(min(float(min(nr, nphi)) / smooth_scale, float(min(nr, nphi))), 1.0)
    filt = np.exp(-0.5 * np.square(k / k_cut))
    field = np.fft.irfft2(spec * filt, s=(nr, nphi)).astype(np.float64)
    field -= float(np.nanmean(field))
    std = float(np.nanstd(field))
    if not np.isfinite(std) or std < 1e-8:
        field = white.astype(np.float64)
        field -= float(np.nanmean(field))
        std = float(np.nanstd(field))
    if std < 1e-8:
        return np.zeros((nr, nphi), dtype=np.float64)
    return np.clip(field / std, -3.5, 3.5)


def _apply_perturb(
    arr: np.ndarray,
    delta_rphi: np.ndarray,
    nr: int,
    nphi: int,
    mode: str,
    amp: float,
) -> np.ndarray:
    x = np.asarray(arr, dtype=np.float64)
    if x.ndim == 1 and x.size == nr * nphi:
        plane = x.reshape(nr, nphi)
        if mode == "log":
            plane = np.maximum(plane, 0.0) * np.exp(amp * delta_rphi)
        else:
            plane = plane * np.maximum(0.05, 1.0 + amp * delta_rphi)
        return plane.reshape(x.shape)

    r_axis, p_axis = _find_rphi_axes(x.shape, nr, nphi, "field")
    moved = np.moveaxis(x, [r_axis, p_axis], [0, 1])
    extra = moved.ndim - 2
    delta = delta_rphi.reshape((nr, nphi) + (1,) * extra)
    if mode == "log":
        moved = np.maximum(moved, 0.0) * np.exp(amp * delta)
    else:
        moved = moved * np.maximum(0.05, 1.0 + amp * delta)
    return np.moveaxis(moved, [0, 1], [r_axis, p_axis])


def _copy_h5(src: Path, dst: Path) -> None:
    with h5py.File(src, "r") as h5_in, h5py.File(dst, "w") as h5_out:
        for k, v in h5_in.attrs.items():
            h5_out.attrs[k] = v
        for key in h5_in.keys():
            h5_in.copy(key, h5_out)


def main() -> None:
    ap = argparse.ArgumentParser(description="Inject correlated initial-condition perturbations into an HDF5 snapshot.")
    ap.add_argument("--input", required=True, help="input HDF5 snapshot path")
    ap.add_argument("--output", required=True, help="output perturbed HDF5 path")
    ap.add_argument("--seed", type=int, default=1337, help="random seed")
    ap.add_argument("--amp", type=float, default=0.0, help="perturbation amplitude (fractional, e.g. 0.15)")
    ap.add_argument("--scale", type=float, default=12.0, help="correlation scale in grid cells (larger => larger clumps)")
    ap.add_argument("--r-key", default="", help="radius dataset key/path")
    ap.add_argument("--phi-key", default="", help="azimuth dataset key/path")
    ap.add_argument("--rho-key", default="", help="density dataset key/path")
    ap.add_argument("--temp-key", default="", help="temperature dataset key/path")
    ap.add_argument("--vr-key", default="", help="radial velocity dataset key/path")
    ap.add_argument("--vphi-key", default="", help="azimuth velocity dataset key/path")
    args = ap.parse_args()

    if h5py is None:
        raise RuntimeError("h5py is required. install with: python3 -m pip install h5py")
    if args.scale <= 0:
        raise ValueError("--scale must be > 0")
    if args.amp < 0:
        raise ValueError("--amp must be >= 0")

    in_path = Path(args.input).expanduser().resolve()
    out_path = Path(args.output).expanduser().resolve()
    out_path.parent.mkdir(parents=True, exist_ok=True)

    _copy_h5(in_path, out_path)
    if args.amp <= 0:
        print(f"amp=0; copied input without perturbation: {out_path}")
        return

    with h5py.File(out_path, "r+") as h5:
        ds_map = _collect_datasets(h5)
        if not ds_map:
            raise ValueError(f"no datasets found in {out_path}")

        r_key = _resolve_key(ds_map, args.r_key, ["r", "radius", "x1v", "x1", "X1", "grid/r"], "radius", True)
        phi_key = _resolve_key(ds_map, args.phi_key, ["phi", "x3v", "x3", "X3", "grid/phi"], "phi", True)
        rho_key = _resolve_key(ds_map, args.rho_key, ["rho", "density", "dens", "RHO", "Density"], "density", True)
        temp_key = _resolve_key(
            ds_map,
            args.temp_key,
            ["temp", "temperature", "temp_scale", "Theta", "theta_e", "Te", "prs", "u", "press", "pressure"],
            "temperature",
            False,
        )
        vr_key = _resolve_key(ds_map, args.vr_key, ["vr", "v_r", "vx1", "u1", "v1", "vel1", "vr_ratio"], "vr", False)
        vphi_key = _resolve_key(
            ds_map, args.vphi_key, ["vphi", "v_phi", "vx3", "u3", "v3", "vel3", "vphi_scale"], "vphi", False
        )

        r = _coord_1d(np.asarray(ds_map[r_key]), "r")
        phi = _coord_1d(np.asarray(ds_map[phi_key]), "phi")
        nr = int(r.size)
        nphi = int(phi.size)
        if nr < 2 or nphi < 2:
            raise ValueError(f"invalid coordinate sizes: r={nr}, phi={nphi}")

        delta = _make_correlated_field(nr, nphi, int(args.seed), float(args.scale))

        edited: List[str] = []
        for key, mode, field_amp in [
            (rho_key, "log", float(args.amp)),
            (temp_key, "log", 0.35 * float(args.amp)),
            (vr_key, "lin", 0.45 * float(args.amp)),
            (vphi_key, "lin", 0.20 * float(args.amp)),
        ]:
            if not key:
                continue
            ds = ds_map.get(key)
            if ds is None:
                continue
            if ds.dtype.kind not in ("f",):
                continue
            raw = np.asarray(ds[...])
            out = _apply_perturb(raw, delta, nr, nphi, mode, field_amp)
            ds[...] = out.astype(ds.dtype, copy=False)
            edited.append(key)

        h5.attrs["blackhole_ic_perturb_seed"] = int(args.seed)
        h5.attrs["blackhole_ic_perturb_amp"] = float(args.amp)
        h5.attrs["blackhole_ic_perturb_scale"] = float(args.scale)
        h5.attrs["blackhole_ic_perturb_fields"] = ",".join(edited)

    fields_txt = ", ".join(edited) if edited else "(none)"
    print(f"saved perturbed hdf5: {out_path}")
    print(f"seed={int(args.seed)} amp={float(args.amp):.6f} scale={float(args.scale):.3f} fields={fields_txt}")


if __name__ == "__main__":
    main()
