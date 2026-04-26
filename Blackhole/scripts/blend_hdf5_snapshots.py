#!/usr/bin/env python3
"""Blend two adjacent GRMHD HDF5 snapshots into one intermediate snapshot.

This is a preprocessing bridge for the existing single-snapshot volume builder.
It preserves the first file's structure and metadata, then replaces compatible
floating physical fields with an interpolated state. Positive thermodynamic
fields are blended in log space because they are multiplicative in code units;
velocity and magnetic components are blended linearly.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
from pathlib import Path
from typing import Dict, Iterable, List, Tuple

import numpy as np

try:
    import h5py  # type: ignore
except Exception:  # pragma: no cover - runtime dependency check
    h5py = None


_COORD_NAMES = {
    "r",
    "radius",
    "rad",
    "theta",
    "th",
    "phi",
    "x",
    "y",
    "z",
    "x1",
    "x2",
    "x3",
    "x1v",
    "x2v",
    "x3v",
    "x1f",
    "x2f",
    "x3f",
    "startx1",
    "startx2",
    "startx3",
    "dx1",
    "dx2",
    "dx3",
}

_POSITIVE_FIELD_NAMES = {
    "rho",
    "density",
    "dens",
    "uu",
    "u",
    "internal_energy",
    "energy",
    "press",
    "pressure",
    "thetae",
    "te",
    "temp",
    "temperature",
    "bmag",
    "bsq",
}

_POSITIVE_PRIMS = {"RHO", "UU"}


def _collect_datasets(h5: "h5py.File") -> Dict[str, "h5py.Dataset"]:
    out: Dict[str, "h5py.Dataset"] = {}

    def visit(name: str, obj: object) -> None:
        if isinstance(obj, h5py.Dataset):
            out[name] = obj

    h5.visititems(visit)
    return out


def _decode_names(values: object) -> List[str]:
    arr = np.asarray(values)
    names: List[str] = []
    for item in arr.reshape(-1):
        raw = item.item() if isinstance(item, np.generic) else item
        if isinstance(raw, bytes):
            names.append(raw.decode("utf-8", errors="replace").strip("\x00").strip())
        else:
            names.append(str(raw).strip("\x00").strip())
    return names


def _read_prim_names(h5: "h5py.File") -> List[str]:
    if "header/prim_names" not in h5:
        return []
    try:
        return [name.upper() for name in _decode_names(h5["header/prim_names"][()])]
    except Exception:
        return []


def _basename(path: str) -> str:
    return path.rsplit("/", 1)[-1].lower()


def _is_compatible(a: "h5py.Dataset", b: "h5py.Dataset") -> bool:
    return a.shape == b.shape and a.dtype.kind in "fc" and b.dtype.kind in "fc"


def _should_blend_dataset(path: str, ds: "h5py.Dataset") -> bool:
    base = _basename(path)
    if path == "prims":
        return ds.ndim == 4
    if ds.shape == ():
        return base in {"t", "time"}
    if path.startswith("header/") and base not in {"t", "time"}:
        return False
    if base in _COORD_NAMES:
        return False
    return ds.dtype.kind in "fc"


def _should_log_blend_name(path: str) -> bool:
    return _basename(path) in _POSITIVE_FIELD_NAMES


def _linear_blend(a: np.ndarray, b: np.ndarray, alpha: float) -> np.ndarray:
    out = (1.0 - alpha) * a + alpha * b
    return np.where(np.isfinite(out), out, a)


def _log_blend_positive(a: np.ndarray, b: np.ndarray, alpha: float) -> np.ndarray:
    floor = 1.0e-30
    linear = _linear_blend(a, b, alpha)
    safe_a = np.maximum(np.asarray(a, dtype=np.float64), floor)
    safe_b = np.maximum(np.asarray(b, dtype=np.float64), floor)
    out = np.exp((1.0 - alpha) * np.log(safe_a) + alpha * np.log(safe_b))
    return np.where(np.isfinite(out), out, linear)


def _write_blend(
    out_ds: "h5py.Dataset",
    next_ds: "h5py.Dataset",
    alpha: float,
    *,
    log_space: bool,
) -> None:
    a = np.asarray(out_ds[()], dtype=np.float64)
    b = np.asarray(next_ds[()], dtype=np.float64)
    blended = _log_blend_positive(a, b, alpha) if log_space else _linear_blend(a, b, alpha)
    out_ds[...] = blended.astype(out_ds.dtype, copy=False)


def _blend_prims(
    out_ds: "h5py.Dataset",
    next_ds: "h5py.Dataset",
    prim_names: Iterable[str],
    alpha: float,
) -> Tuple[int, int]:
    names = list(prim_names)
    n_prim = int(out_ds.shape[-1])
    blended = 0
    log_blended = 0
    for i in range(n_prim):
        name = names[i].upper() if i < len(names) else ""
        log_space = name in _POSITIVE_PRIMS
        a = np.asarray(out_ds[..., i], dtype=np.float64)
        b = np.asarray(next_ds[..., i], dtype=np.float64)
        value = _log_blend_positive(a, b, alpha) if log_space else _linear_blend(a, b, alpha)
        out_ds[..., i] = value.astype(out_ds.dtype, copy=False)
        blended += 1
        if log_space:
            log_blended += 1
    return blended, log_blended


def blend_snapshots(input_path: Path, input_next_path: Path, output_path: Path, alpha: float, force: bool) -> Dict[str, object]:
    if h5py is None:
        raise RuntimeError("h5py is required. install with: python3 -m pip install h5py")
    if not input_path.is_file():
        raise FileNotFoundError(f"input not found: {input_path}")
    if not input_next_path.is_file():
        raise FileNotFoundError(f"input-next not found: {input_next_path}")
    if alpha < 0.0 or alpha > 1.0:
        raise ValueError("time-blend must be in [0, 1]")
    if output_path.exists() and not force:
        raise FileExistsError(f"output already exists: {output_path} (use --force to overwrite)")

    output_path.parent.mkdir(parents=True, exist_ok=True)
    tmp_path = output_path.with_name(f".{output_path.name}.tmp-{os.getpid()}")
    if tmp_path.exists():
        tmp_path.unlink()
    if output_path.exists():
        output_path.unlink()

    stats = {
        "datasetsBlended": 0,
        "datasetsLogBlended": 0,
        "primitiveComponentsBlended": 0,
        "primitiveComponentsLogBlended": 0,
        "skippedShapeMismatch": 0,
        "skippedNonPhysical": 0,
    }
    examples: List[str] = []

    try:
        shutil.copy2(input_path, tmp_path)
        with h5py.File(tmp_path, "r+") as out_h5, h5py.File(input_next_path, "r") as next_h5:
            out_map = _collect_datasets(out_h5)
            next_map = _collect_datasets(next_h5)
            prim_names = _read_prim_names(out_h5)

            for path, out_ds in out_map.items():
                if path not in next_map:
                    continue
                next_ds = next_map[path]
                if not _is_compatible(out_ds, next_ds):
                    stats["skippedShapeMismatch"] += 1
                    continue
                if not _should_blend_dataset(path, out_ds):
                    stats["skippedNonPhysical"] += 1
                    continue
                if path == "prims":
                    n, n_log = _blend_prims(out_ds, next_ds, prim_names, alpha)
                    stats["primitiveComponentsBlended"] += n
                    stats["primitiveComponentsLogBlended"] += n_log
                    examples.append("prims")
                    continue
                log_space = _should_log_blend_name(path)
                _write_blend(out_ds, next_ds, alpha, log_space=log_space)
                stats["datasetsBlended"] += 1
                if log_space:
                    stats["datasetsLogBlended"] += 1
                if len(examples) < 12:
                    examples.append(path)

            out_h5.attrs["blackholeTemporalBlendEnabled"] = True
            out_h5.attrs["blackholeTemporalBlendInput"] = str(input_path)
            out_h5.attrs["blackholeTemporalBlendInputNext"] = str(input_next_path)
            out_h5.attrs["blackholeTemporalBlendAlpha"] = float(alpha)
            out_h5.attrs["blackholeTemporalBlendNote"] = (
                "Positive thermodynamic primitive fields use log-space interpolation; "
                "velocity and magnetic primitive fields use linear interpolation."
            )
        tmp_path.replace(output_path)
    except Exception:
        tmp_path.unlink(missing_ok=True)
        raise

    return {
        "output": str(output_path),
        "input": str(input_path),
        "inputNext": str(input_next_path),
        "timeBlend": float(alpha),
        "stats": stats,
        "examples": examples,
    }


def main() -> None:
    ap = argparse.ArgumentParser(description="Blend adjacent GRMHD HDF5 snapshots for single-snapshot volume preprocessing")
    ap.add_argument("--input", required=True, help="first HDF5 snapshot")
    ap.add_argument("--input-next", required=True, help="next HDF5 snapshot")
    ap.add_argument("--output", required=True, help="output blended HDF5 snapshot")
    ap.add_argument("--time-blend", type=float, required=True, help="blend factor in [0, 1]")
    ap.add_argument("--force", action="store_true", help="overwrite output if it already exists")
    args = ap.parse_args()

    result = blend_snapshots(
        Path(args.input).expanduser().resolve(),
        Path(args.input_next).expanduser().resolve(),
        Path(args.output).expanduser().resolve(),
        float(args.time_blend),
        bool(args.force),
    )
    print(json.dumps(result, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
