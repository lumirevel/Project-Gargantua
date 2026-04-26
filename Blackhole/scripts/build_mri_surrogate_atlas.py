#!/usr/bin/env python3
"""Build a lightweight evolved 2D disk-state atlas for the visible thin-disk source.

This is a surrogate disk-state generator, not a decorative image texture.  It
creates positive, disk-coordinate heating/column proxies from localized
Kepler-sheared events and writes the renderer's float4 atlas format:

  R: temperature scale / hardening proxy
  G: column/heating activity proxy in [0, 1]
  B: radial velocity proxy
  A: azimuthal velocity scale

The field is intended as a fallback until real evolved MHD/GRMHD surface data is
available.  It is temporally coherent through --time because packet centers are
advected by Omega_K(r_c).
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np


def wrap_pi(x: np.ndarray) -> np.ndarray:
    return (x + np.pi) % (2.0 * np.pi) - np.pi


def fract(x: np.ndarray | float) -> np.ndarray | float:
    return np.modf(x)[0]


def exposure_samples(args: argparse.Namespace) -> tuple[np.ndarray, np.ndarray]:
    """Return deterministic finite-exposure sample offsets and normalized weights.

    A zero exposure or one time sample reproduces the previous instantaneous
    packet field.  For longer exposures, a Hann shutter suppresses hard endpoints
    so packet advection creates a physically interpretable finite-integration
    stress/heating atlas instead of a single frozen surface pattern.
    """
    samples = max(1, int(args.time_samples))
    exposure = max(0.0, float(args.exposure_time))
    if samples <= 1 or exposure <= 0.0:
        return np.array([0.0], dtype=np.float64), np.array([1.0], dtype=np.float64)

    centers = (np.arange(samples, dtype=np.float64) + 0.5) / samples
    offsets = (centers - 0.5) * exposure
    weights = 0.5 - 0.5 * np.cos(2.0 * np.pi * centers)
    weights /= np.sum(weights)
    return offsets, weights


def build_atlas(args: argparse.Namespace) -> np.ndarray:
    width = args.width
    height = args.height
    phi = (np.arange(width, dtype=np.float64) + 0.5) / width * 2.0 * np.pi
    y = (np.arange(height, dtype=np.float64) + 0.5) / height
    # Inverse of disk_sample_atlas(): sample uses r01^r_warp as texture y.
    r01 = np.power(np.clip(y, 0.0, 1.0), 1.0 / max(args.r_warp, 1e-6))
    r = args.r_min + (args.r_max - args.r_min) * r01
    log_r = np.log(np.maximum(r / max(args.r_min, 1e-6), 1.0001))
    log_r_max = float(np.log(max(args.r_max / max(args.r_min, 1e-6), 1.05)))

    rr = r[:, None]
    lr = log_r[:, None]
    pp = phi[None, :]

    hot = np.zeros((height, width), dtype=np.float64)
    broad = np.zeros_like(hot)
    radial_v = np.zeros_like(hot)
    vort = np.zeros_like(hot)

    sample_offsets, sample_weights = exposure_samples(args)

    for i in range(args.packets):
        idx = float(i + 1)
        h0 = fract(idx * 0.754877666)
        h1 = fract(idx * 0.569840291 + 0.217)
        h2 = fract(idx * 0.438572245 + 0.431)
        h3 = fract(idx * 0.318309886 + 0.173)
        h4 = fract(idx * 0.221033321 + 0.619)
        h5 = fract(idx * 0.141421356 + 0.347)
        h6 = fract(idx * 0.097887032 + 0.827)

        log_rc = (0.05 + 0.88 * h0) * log_r_max
        r_c = args.r_min * np.exp(log_rc)
        omega_c = args.omega * max(r_c, 1.0) ** -1.5
        phi_base = 2.0 * np.pi * h1
        phase_drift = 0.08 * (h2 - 0.5)
        sig_r = args.sigma_r * (0.70 + 1.20 * h3)
        sig_phi = args.sigma_phi * (0.65 + 1.45 * h4)
        shear = args.shear * (2.0 * h5 - 1.0)
        amp = (0.55 + 1.10 * h6) * np.exp(-args.radial_decay * log_rc)

        for dt, shutter_w in zip(sample_offsets, sample_weights):
            t = args.time + dt
            phi_c = phi_base + omega_c * t + phase_drift * t
            dlog = lr - log_rc
            dphi = wrap_pi(pp - phi_c - shear * dlog)
            q = (dlog / max(sig_r, 1e-6)) ** 2 + (dphi / max(sig_phi, 1e-6)) ** 2
            core = np.clip(1.0 - 0.58 * q, 0.0, 1.0)
            core = core * core * (3.0 - 2.0 * core)

            broad_r = 3.2 * sig_r
            broad_phi = 2.8 * sig_phi
            qb = (dlog / max(broad_r, 1e-6)) ** 2 + (dphi / max(broad_phi, 1e-6)) ** 2
            env = np.clip(1.0 - 0.36 * qb, 0.0, 1.0)
            env = env * env

            hot += shutter_w * amp * core
            broad += shutter_w * amp * env
            # Simple stress/vorticity proxies for velocity channels. They are bounded
            # diagnostic state, not direct relativistic velocity replacement.
            radial_v += shutter_w * amp * core * np.sign(dphi) * np.exp(-0.5 * (dlog / max(2.0 * sig_r, 1e-6)) ** 2)
            vort += shutter_w * amp * core * np.sign(dlog)

    hot /= max(np.percentile(hot, 99.0), 1e-9)
    broad /= max(np.percentile(broad, 99.0), 1e-9)
    hot = np.clip(hot, 0.0, 1.0)
    broad = np.clip(broad, 0.0, 1.0)

    # Keep the column field centered but with positive high-activity tails. The
    # renderer quantile mapping will further adapt this to cloudNorm.
    column = np.clip(0.30 + args.column_strength * broad + args.hot_strength * hot, 0.0, 1.0)
    temp_scale = np.clip(1.0 + args.temp_strength * hot + 0.06 * (broad - broad.mean()), 0.72, 1.42)
    vr = np.clip(args.vr_strength * radial_v / max(np.percentile(np.abs(radial_v), 99.0), 1e-9), -1.0, 1.0)
    vphi = np.clip(1.0 + args.vphi_strength * vort / max(np.percentile(np.abs(vort), 99.0), 1e-9), 0.65, 1.35)

    atlas = np.zeros((height, width, 4), dtype=np.float32)
    atlas[..., 0] = temp_scale.astype(np.float32)
    atlas[..., 1] = column.astype(np.float32)
    atlas[..., 2] = vr.astype(np.float32)
    atlas[..., 3] = vphi.astype(np.float32)
    return atlas


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--output", required=True)
    p.add_argument("--width", type=int, default=1024)
    p.add_argument("--height", type=int, default=512)
    p.add_argument("--r-min", type=float, default=1.0)
    p.add_argument("--r-max", type=float, default=8.2)
    p.add_argument("--r-warp", type=float, default=0.65)
    p.add_argument("--time", type=float, default=0.0)
    p.add_argument("--exposure-time", type=float, default=0.0,
                   help="Finite shutter duration in code time units; 0 keeps an instantaneous atlas.")
    p.add_argument("--time-samples", type=int, default=1,
                   help="Number of Hann-weighted temporal samples used for finite-exposure atlas averaging.")
    p.add_argument("--packets", type=int, default=96)
    p.add_argument("--omega", type=float, default=1.0)
    p.add_argument("--sigma-r", type=float, default=0.045)
    p.add_argument("--sigma-phi", type=float, default=0.095)
    p.add_argument("--shear", type=float, default=2.6)
    p.add_argument("--radial-decay", type=float, default=0.30)
    p.add_argument("--column-strength", type=float, default=0.28)
    p.add_argument("--hot-strength", type=float, default=0.42)
    p.add_argument("--temp-strength", type=float, default=0.22)
    p.add_argument("--vr-strength", type=float, default=0.08)
    p.add_argument("--vphi-strength", type=float, default=0.06)
    args = p.parse_args()

    if args.width <= 0 or args.height <= 0:
        raise ValueError("width/height must be positive")
    if args.r_max <= args.r_min:
        raise ValueError("r-max must exceed r-min")

    atlas = build_atlas(args)
    out = Path(args.output).expanduser().resolve()
    out.parent.mkdir(parents=True, exist_ok=True)
    atlas.tofile(out)
    meta = {
        "width": args.width,
        "height": args.height,
        "format": "float4",
        "channels": ["temp_scale", "column_activity", "vr_proxy", "vphi_scale"],
        "model": "mri_surrogate_2d_shearing_packets_v1",
        "rNormMin": args.r_min,
        "rNormMax": args.r_max,
        "rNormWarp": args.r_warp,
        "time": args.time,
        "exposureTime": args.exposure_time,
        "timeSamples": args.time_samples,
        "packets": args.packets,
        "notes": "Fallback evolved disk-state atlas; source emissivity proxy, not screen texture.",
    }
    with Path(str(out) + ".json").open("w", encoding="utf-8") as f:
        json.dump(meta, f, ensure_ascii=True, indent=2, sort_keys=True)
    print(f"saved atlas: {out} ({args.width}x{args.height})")
    print(f"saved meta: {out}.json")


if __name__ == "__main__":
    main()
