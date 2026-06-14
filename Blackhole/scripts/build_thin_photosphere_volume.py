#!/usr/bin/env python3
"""Build a deterministic thin photospheric volume for precision-mode volume RT.

This is a fallback/surrogate fluid field, not evolved GRMHD truth.  It writes the
same legacy float4 volume schema as build_hdf5_volume.py:
  channel 0: temp_scale
  channel 1: density
  channel 2: vr_ratio
  channel 3: vphi_scale

The field is periodic in phi and defined in disk/world space so visual structure
moves with the disk model rather than being painted in image space.
"""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

import numpy as np


def smoothstep(edge0: float, edge1: float, x: np.ndarray) -> np.ndarray:
    t = np.clip((x - edge0) / max(edge1 - edge0, 1.0e-12), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def parse_args() -> argparse.Namespace:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--output", required=True)
    ap.add_argument("--nr", type=int, default=128)
    ap.add_argument("--nphi", type=int, default=256)
    ap.add_argument("--nz", type=int, default=72)
    ap.add_argument("--r-min", type=float, default=2.15)
    ap.add_argument("--r-max", type=float, default=22.0)
    ap.add_argument("--r-warp", type=float, default=0.72)
    ap.add_argument("--z-max", type=float, default=0.16)
    ap.add_argument("--h-over-r", type=float, default=0.055)
    ap.add_argument("--h-over-r-inner", type=float, default=0.045)
    ap.add_argument("--h-over-r-outer", type=float, default=0.070)
    ap.add_argument("--density-power", type=float, default=1.15)
    ap.add_argument("--temp-power", type=float, default=0.72)
    ap.add_argument("--contrast", type=float, default=1.05)
    ap.add_argument("--heating-strength", type=float, default=0.70)
    ap.add_argument("--stream-strength", type=float, default=0.85)
    ap.add_argument("--continuum-floor", type=float, default=0.26)
    ap.add_argument("--time", type=float, default=0.0)
    ap.add_argument("--inflow", type=float, default=0.050)
    ap.add_argument("--vphi-drop", type=float, default=0.055)
    ap.add_argument("--seed-phase", type=float, default=0.0)
    return ap.parse_args()


def validate_args(a: argparse.Namespace) -> None:
    if a.nr < 2 or a.nphi < 4 or a.nz < 2:
        raise SystemExit("nr/nphi/nz are too small")
    if not (a.r_max > a.r_min > 0.0):
        raise SystemExit("require 0 < r-min < r-max")
    if not (a.z_max > 0.0):
        raise SystemExit("require z-max > 0")
    if not (a.h_over_r > 0.0 and a.h_over_r_inner > 0.0 and a.h_over_r_outer > 0.0):
        raise SystemExit("h-over-r values must be positive")


def build_volume(a: argparse.Namespace) -> np.ndarray:
    # Store radial samples with the same logical axes as build_hdf5_volume.py:
    # binary order is (z, phi, r, float4).
    u = np.linspace(0.0, 1.0, a.nr, dtype=np.float64)
    r = a.r_min + (a.r_max - a.r_min) * np.power(u, max(a.r_warp, 1.0e-6))
    phi = np.linspace(0.0, 2.0 * math.pi, a.nphi, endpoint=False, dtype=np.float64)
    z = np.linspace(-a.z_max, a.z_max, a.nz, dtype=np.float64)

    rr = r[None, :]
    pp = phi[:, None]
    zz = z[:, None, None]

    r01 = np.clip((rr - a.r_min) / max(a.r_max - a.r_min, 1.0e-12), 0.0, 1.0)
    h_over_r = (a.h_over_r
                + (a.h_over_r_inner - a.h_over_r) * (1.0 - r01) ** 1.4
                + (a.h_over_r_outer - a.h_over_r) * r01 ** 1.2)
    h = np.maximum(h_over_r * rr, 1.0e-4)
    zeta = zz / h[None, :, :]

    vertical_density = np.exp(-0.5 * zeta * zeta)
    vertical_temp = np.exp(-0.12 * zeta * zeta)
    photosphere_shell = np.exp(-0.5 * (zeta / 1.25) ** 2)

    inner = smoothstep(a.r_min, a.r_min + 0.75, rr)
    outer = 1.0 - smoothstep(a.r_max - 5.0, a.r_max, rr)
    radial_density = inner * outer * np.power(np.maximum(rr / a.r_min, 1.0), -a.density_power)
    radial_temp = np.power(np.maximum(rr / a.r_min, 1.0), -a.temp_power)

    # Deterministic sheared modes. These are not evolved GRMHD, but they are
    # periodic disk-space perturbations and preserve differential rotation cues.
    omega = np.power(np.maximum(rr / a.r_min, 1.0), -1.5)
    phase = pp - 0.85 * a.time * omega + a.seed_phase
    log_r = np.log(np.maximum(rr / a.r_min, 1.0e-6))
    modes = (
        0.55 * np.cos(2.0 * phase + 2.10 * log_r + 0.4)
        + 0.34 * np.cos(3.0 * phase - 1.35 * log_r + 1.7)
        + 0.24 * np.cos(5.0 * phase + 3.60 * log_r + 2.5)
        + 0.15 * np.cos(8.0 * phase - 5.25 * log_r + 0.9)
        + 0.10 * np.cos(13.0 * phase + 7.10 * log_r + 2.2)
        + 0.07 * np.cos(21.0 * phase - 9.80 * log_r + 0.1)
    )
    modes /= 1.42
    spiral = np.tanh(modes)

    # Coherent disk-space density waves. These are deterministic radial/spiral
    # modes rather than image-space noise; they model unresolved pressure/MRI
    # structure that should survive line-of-sight integration better than pure
    # azimuthal striping.
    radial_wave = (
        0.46 * np.cos(9.0 * log_r - 0.55 * a.time + 0.2)
        + 0.30 * np.cos(15.5 * log_r + 0.9 * phase + 1.1)
        + 0.18 * np.cos(27.0 * log_r - 1.7 * phase + 2.4)
    ) / 0.94
    radial_wave = np.tanh(radial_wave)

    # Large-scale spiral streams are deliberately low-m modes. Fine structure is
    # averaged away by lensing + line-of-sight integration; these coherent arms
    # are the rendering-layer analogue of unresolved density/pressure waves in a
    # thin participating flow, not an image-space texture.
    stream_phase = phase + 0.62 * log_r
    stream_a = np.cos(1.0 * stream_phase - 1.25 * log_r + 0.8)
    stream_b = np.cos(2.0 * stream_phase + 2.15 * log_r + 2.1)
    stream_c = np.cos(3.0 * stream_phase - 0.75 * log_r + 0.4)
    stream = np.tanh(0.74 * stream_a + 0.44 * stream_b + 0.24 * stream_c)
    stream_filament = smoothstep(-0.10, 0.82, stream)
    stream_rarefaction = 1.0 - 0.24 * smoothstep(0.08, 0.92, -stream)

    vortices = np.zeros_like(phase)
    # (radius/rs, phi0, amplitude, log-r width, phi width, shear rate)
    vortex_specs = (
        (3.4, 0.35,  0.85, 0.16, 0.28, 1.45),
        (4.8, 2.10, -0.55, 0.18, 0.34, 1.10),
        (6.2, 4.85,  0.65, 0.22, 0.42, 0.82),
        (8.8, 1.30,  0.50, 0.26, 0.55, 0.58),
        (12.5, 3.80, -0.42, 0.32, 0.68, 0.42),
        (16.5, 5.40,  0.36, 0.36, 0.78, 0.31),
    )
    for rc, phic, amp, sr, sp, shear in vortex_specs:
        rc_log = math.log(max(rc / a.r_min, 1.0e-6))
        omega_c = (max(rc / a.r_min, 1.0e-6)) ** -1.5
        phi_c = phic + a.seed_phase + shear * a.time * omega_c
        dphi = np.arctan2(np.sin(pp - phi_c), np.cos(pp - phi_c))
        dr = log_r - rc_log
        vortices += amp * np.exp(-0.5 * ((dr / sr) ** 2 + (dphi / sp) ** 2))
    vortices = np.tanh(vortices)

    structure = np.tanh(0.40 * spiral
                        + 0.34 * radial_wave
                        + 0.52 * vortices
                        + a.stream_strength * 0.82 * stream)
    clump = np.exp(np.clip(a.contrast * structure, -0.80, 0.82))
    filament = smoothstep(-0.30, 0.82, structure)
    gaps = 1.0 - 0.38 * smoothstep(0.12, 0.92, -structure)
    rings = 0.72 + 0.28 * smoothstep(-0.55, 0.75, radial_wave)
    vertical_texture = 1.0 + 0.13 * np.cos(2.0 * math.pi * zeta + 0.7 * spiral[None, :, :])

    structured_density = (
        radial_density[None, :, :]
        * vertical_density
        * photosphere_shell
        * clump[None, :, :]
        * (0.50 + 0.50 * filament[None, :, :])
        * (0.60 + 0.82 * stream_filament[None, :, :])
        * stream_rarefaction[None, :, :]
        * gaps[None, :, :]
        * rings[None, :, :]
        * vertical_texture
    )
    continuum_density = (
        radial_density[None, :, :]
        * vertical_density
        * photosphere_shell
        * (0.86 + 0.14 * rings[None, :, :])
    )
    # The disk is participating gas, not isolated glowing clumps. Keep a
    # photospheric continuum so cooler/rarefied flow still emits and absorbs,
    # while the sheared streams modulate that baseline.
    density = structured_density + max(a.continuum_floor, 0.0) * continuum_density
    density = density / max(float(np.percentile(density, 99.5)), 1.0e-12)
    density = np.clip(density, 0.0, 1.0)
    density = np.power(density, 1.12)

    # Couple unresolved flow structure to thermal state through a conservative
    # compressive-heating proxy. This keeps the field deterministic and
    # disk-space based: dense/sheared/vortical regions become slightly hotter
    # instead of acting only as grey opacity. It is still a surrogate, not a
    # replacement for evolved MHD temperature.
    compression_proxy = np.clip(
        clump
        * (0.72 + 0.28 * rings)
        * (0.68 + 0.32 * smoothstep(-0.25, 0.85, structure))
        * (0.78 + 0.44 * stream_filament),
        0.18,
        4.0,
    )
    adiabatic_heat = np.power(compression_proxy, 0.32)
    shear_heat = 1.0 + a.heating_strength * 0.28 * smoothstep(0.05, 0.95, structure) * np.power(1.0 - r01, 0.35)
    vortex_heat = 1.0 + a.heating_strength * 0.18 * np.maximum(vortices, 0.0) * np.power(1.0 - r01, 0.25)
    stream_heat = 1.0 + a.heating_strength * 0.38 * stream_filament * np.power(1.0 - r01, 0.28)
    wave_cool = 1.0 - a.heating_strength * 0.10 * smoothstep(0.10, 0.95, -structure)
    temp_phase = np.exp(np.clip(0.34 * a.contrast * structure + 0.12 * radial_wave, -0.38, 0.48))
    temp_scale_2d = radial_temp * adiabatic_heat * shear_heat * vortex_heat * stream_heat * wave_cool * temp_phase
    temp_scale = temp_scale_2d[None, :, :] * vertical_temp
    temp_scale = temp_scale / max(float(np.percentile(temp_scale, 92.0)), 1.0e-12)
    temp_scale = np.clip(temp_scale, 0.16, 4.2)

    vr_ratio_2d = -a.inflow * (0.55 + 0.45 * (1.0 - inner)) * (1.0 + 0.14 * structure)
    vphi_scale_2d = 1.0 - a.vphi_drop * np.clip(np.abs(zeta), 0.0, 2.0) / 2.0
    vphi_scale_2d = vphi_scale_2d * (1.0 + 0.018 * structure[None, :, :])

    vol = np.zeros((a.nz, a.nphi, a.nr, 4), dtype=np.float32)
    vol[..., 0] = temp_scale.astype(np.float32)
    vol[..., 1] = density.astype(np.float32)
    vol[..., 2] = np.clip(vr_ratio_2d[None, :, :], -0.25, 0.05).astype(np.float32)
    vol[..., 3] = np.clip(vphi_scale_2d, 0.65, 1.15).astype(np.float32)
    return vol


def main() -> int:
    args = parse_args()
    validate_args(args)
    vol = build_volume(args)

    out = Path(args.output)
    out.parent.mkdir(parents=True, exist_ok=True)
    vol.tofile(out)

    meta = {
        "r": args.nr,
        "phi": args.nphi,
        "z": args.nz,
        "format": "float4",
        "channels": ["temp_scale", "density", "vr_ratio", "vphi_scale"],
        "source": "analytic-thin-photosphere-volume-surrogate",
        "rNormMin": float(args.r_min),
        "rNormMax": float(args.r_max),
        "zNormMax": float(args.z_max),
        "rNormWarp": float(args.r_warp),
        "model": {
            "type": "thin-photospheric-participating-medium",
            "hOverR": float(args.h_over_r),
            "hOverRInner": float(args.h_over_r_inner),
            "hOverROuter": float(args.h_over_r_outer),
            "contrast": float(args.contrast),
            "heatingStrength": float(args.heating_strength),
            "streamStrength": float(args.stream_strength),
            "continuumFloor": float(args.continuum_floor),
            "time": float(args.time),
            "structureModes": "low-m sheared streams + radial density waves + deterministic advected vortices + compressive heating proxy",
            "assumption": "surrogate disk-space field; replace with evolved GRMHD/fluid data when available",
        },
        "stats": {
            "tempScaleMin": float(np.min(vol[..., 0])),
            "tempScaleP50": float(np.percentile(vol[..., 0], 50.0)),
            "tempScaleP99": float(np.percentile(vol[..., 0], 99.0)),
            "densityMin": float(np.min(vol[..., 1])),
            "densityP50": float(np.percentile(vol[..., 1], 50.0)),
            "densityP99": float(np.percentile(vol[..., 1], 99.0)),
        },
    }
    with Path(str(out) + ".json").open("w", encoding="utf-8") as f:
        json.dump(meta, f, ensure_ascii=True, indent=2, sort_keys=True)

    print(f"saved thin photosphere volume: {out} ({args.nr}x{args.nphi}x{args.nz})")
    print(f"rNorm=[{args.r_min:.4f}, {args.r_max:.4f}], zNormMax={args.z_max:.4f}, H/R={args.h_over_r:.4f}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
