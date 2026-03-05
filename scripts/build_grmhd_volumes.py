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


def _resolve_optional_key(
    ds_map: Dict[str, "h5py.Dataset"],
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
    ds_map: Dict[str, "h5py.Dataset"],
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
    ds_map: Dict[str, "h5py.Dataset"],
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
    ap.add_argument("--z-max", type=float, default=0.35, help="maximum |z|/rs in output")
    ap.add_argument("--r-to-rs", type=float, default=1.0, help="multiplier to convert input radius to r/rs")
    ap.add_argument("--theta-index", type=int, default=-1, help="theta index for extra dimensions (-1=mid)")
    ap.add_argument("--theta-average", action="store_true", help="average extra axes instead of slicing")
    ap.add_argument("--theta-key", default="", help="theta/polar coordinate dataset key/path")
    ap.add_argument("--native-3d", choices=["auto", "on", "off"], default="auto", help="use native 3D (r,theta,phi) sampling path")
    ap.add_argument("--u-to-thetae", type=float, default=1.0, help="scale factor for thetae when deriving from internal energy u")
    ap.add_argument("--list-datasets", action="store_true", help="list dataset keys and exit")
    ap.add_argument("--r-key", default="", help="radius dataset key/path")
    ap.add_argument("--phi-key", default="", help="azimuth dataset key/path")
    ap.add_argument("--rho-key", default="", help="density dataset key/path")
    ap.add_argument("--thetae-key", default="", help="electron temperature dataset key/path")
    ap.add_argument("--u-key", default="", help="internal energy dataset key/path (used when thetae is absent)")
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

    in_path = Path(args.input).expanduser().resolve()
    vol0_path = Path(args.vol0).expanduser().resolve()
    vol1_path = Path(args.vol1).expanduser().resolve()
    meta_path = Path(args.meta).expanduser().resolve()

    thetae_key: Optional[str] = None
    u_key: Optional[str] = None
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
            if thetae_3d is None:
                if u_3d is None:
                    thetae_3d = np.full((nr_src, nth_src, nphi_src), 0.08, dtype=np.float64)
                else:
                    thetae_3d = args.u_to_thetae * np.maximum(u_3d, 1e-20)

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

            r_norm_src = np.asarray(r, dtype=np.float64) * args.r_to_rs
            src_r_min = float(np.nanmin(r_norm_src))
            src_r_max = float(np.nanmax(r_norm_src))
            r_min = src_r_min if args.r_min <= 0.0 else float(args.r_min)
            r_max = src_r_max if args.r_max <= 0.0 else float(args.r_max)
            if not (r_max > r_min):
                raise ValueError(f"invalid radial range: r_min={r_min}, r_max={r_max}")
            r_dst = np.linspace(r_min, r_max, args.nr, dtype=np.float64)
            z_dst = np.linspace(-args.z_max, args.z_max, args.nz, dtype=np.float64)

            rho_dst = _sample_cube_to_rphiz(np.maximum(rho_3d, 1e-30), r_norm_src, theta, r_dst, z_dst, args.nphi)
            thetae_dst = _sample_cube_to_rphiz(np.maximum(thetae_3d, 1e-8), r_norm_src, theta, r_dst, z_dst, args.nphi)
            vr_dst = _sample_cube_to_rphiz(vr_3d, r_norm_src, theta, r_dst, z_dst, args.nphi)
            vphi_dst = _sample_cube_to_rphiz(vphi_3d, r_norm_src, theta, r_dst, z_dst, args.nphi)
            vz_dst = _sample_cube_to_rphiz(vz_3d, r_norm_src, theta, r_dst, z_dst, args.nphi)
            br_dst = _sample_cube_to_rphiz(br_3d, r_norm_src, theta, r_dst, z_dst, args.nphi)
            bphi_dst = _sample_cube_to_rphiz(bphi_3d, r_norm_src, theta, r_dst, z_dst, args.nphi)
            bz_dst = _sample_cube_to_rphiz(bz_3d, r_norm_src, theta, r_dst, z_dst, args.nphi)

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
            if thetae_2d is None:
                if u_2d is None:
                    thetae_2d = np.full((nr_src, nphi_src), 0.08, dtype=np.float64)
                else:
                    thetae_2d = args.u_to_thetae * np.maximum(u_2d, 1e-20)

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

            r_norm_src = np.asarray(r, dtype=np.float64) * args.r_to_rs
            src_r_min = float(np.nanmin(r_norm_src))
            src_r_max = float(np.nanmax(r_norm_src))
            r_min = src_r_min if args.r_min <= 0.0 else float(args.r_min)
            r_max = src_r_max if args.r_max <= 0.0 else float(args.r_max)
            if not (r_max > r_min):
                raise ValueError(f"invalid radial range: r_min={r_min}, r_max={r_max}")

            r_dst = np.linspace(r_min, r_max, args.nr, dtype=np.float64)
            rho_dst = _resample_rphi(np.maximum(rho_2d, 1e-30), r_norm_src, r_dst, args.nphi)
            thetae_dst = _resample_rphi(np.maximum(thetae_2d, 1e-8), r_norm_src, r_dst, args.nphi)
            vr_dst = _resample_rphi(vr_2d, r_norm_src, r_dst, args.nphi)
            vphi_dst = _resample_rphi(vphi_2d, r_norm_src, r_dst, args.nphi)
            vz_dst = _resample_rphi(vz_2d, r_norm_src, r_dst, args.nphi)
            br_dst = _resample_rphi(br_2d, r_norm_src, r_dst, args.nphi)
            bphi_dst = _resample_rphi(bphi_2d, r_norm_src, r_dst, args.nphi)
            bz_dst = _resample_rphi(bz_2d, r_norm_src, r_dst, args.nphi)

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
        "vr": vr_key if vr_key is not None else "",
        "vphi": vphi_key if vphi_key is not None else "",
        "vz": vz_key if vz_key is not None else "",
        "br": br_key if br_key is not None else "",
        "bphi": bphi_key if bphi_key is not None else "",
        "bz": bz_key if bz_key is not None else "",
    }
    meta = {
        "format": "grmhd_dual_float4_v1",
        "r": args.nr,
        "phi": args.nphi,
        "z": args.nz,
        "rNormMin": float(r_min),
        "rNormMax": float(r_max),
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
    if use_native_3d:
        print("mapping: native 3D r-theta-phi -> r-phi-z (theta from z/r)")
    elif native_3d_reason:
        print(f"mapping: fallback 2D profile ({native_3d_reason})")


if __name__ == "__main__":
    main()

