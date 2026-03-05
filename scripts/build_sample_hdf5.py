#!/usr/bin/env python3
"""
Build a physically motivated Fishbone-Moncrief torus initial condition in Kerr-Schild coordinates.

Code units: G = c = M = 1.

Outputs an HDF5 snapshot containing:
  - rho, p (and aliases), u^mu, B^i, b^mu
  - low-amplitude density perturbation (MRI trigger)
  - diagnostics for divB, beta, sigma
"""

from __future__ import annotations

import argparse
import math
from pathlib import Path
from typing import Dict, Tuple

import numpy as np

try:
    import h5py  # type: ignore
except Exception:  # pragma: no cover - runtime dependency check
    h5py = None


PI = math.pi
TWOPI = 2.0 * PI


def kerr_horizon_radius(a: float) -> float:
    aa = max(min(a, 0.999), -0.999)
    return 1.0 + math.sqrt(max(1.0 - aa * aa, 0.0))


def metric_ks_2d(r: np.ndarray, th: np.ndarray, a: float) -> Dict[str, np.ndarray]:
    """Covariant Kerr-Schild metric components for (t, r, theta, phi)."""
    s = np.sin(th)
    c = np.cos(th)
    s2 = s * s
    sigma = r * r + (a * a) * (c * c)
    f = (2.0 * r) / np.maximum(sigma, 1e-30)

    gtt = -(1.0 - f)
    gtr = f
    gtphi = -a * f * s2
    grr = 1.0 + f
    grphi = -a * (1.0 + f) * s2
    gthth = sigma
    gphph = s2 * (sigma + (a * a) * (1.0 + f) * s2)

    det_gamma = gthth * np.maximum(grr * gphph - grphi * grphi, 1e-30)
    return {
        "gtt": gtt,
        "gtr": gtr,
        "gtphi": gtphi,
        "grr": grr,
        "grphi": grphi,
        "gthth": gthth,
        "gphph": gphph,
        "det_gamma": det_gamma,
    }


def finite_diff(arr: np.ndarray, x: np.ndarray, axis: int) -> np.ndarray:
    out = np.empty_like(arr)
    if axis == 0:
        out[1:-1, :] = (arr[2:, :] - arr[:-2, :]) / np.maximum((x[2:] - x[:-2])[:, None], 1e-30)
        out[0, :] = (arr[1, :] - arr[0, :]) / max(x[1] - x[0], 1e-30)
        out[-1, :] = (arr[-1, :] - arr[-2, :]) / max(x[-1] - x[-2], 1e-30)
    elif axis == 1:
        out[:, 1:-1] = (arr[:, 2:] - arr[:, :-2]) / np.maximum((x[2:] - x[:-2])[None, :], 1e-30)
        out[:, 0] = (arr[:, 1] - arr[:, 0]) / max(x[1] - x[0], 1e-30)
        out[:, -1] = (arr[:, -1] - arr[:, -2]) / max(x[-1] - x[-2], 1e-30)
    else:
        raise ValueError("axis must be 0 or 1")
    return out


def circular_l_at_equator(r: float, a: float) -> float:
    th = np.array([[0.5 * PI]], dtype=np.float64)
    rr = np.array([[r]], dtype=np.float64)
    g = metric_ks_2d(rr, th, a)
    gtt = float(g["gtt"][0, 0])
    gtphi = float(g["gtphi"][0, 0])
    gphph = float(g["gphph"][0, 0])

    omega = 1.0 / max(r ** 1.5 + a, 1e-12)
    norm = -(gtt + 2.0 * gtphi * omega + gphph * omega * omega)
    if norm <= 0.0:
        raise ValueError(f"invalid circular orbit normalization at r={r}")
    ut = 1.0 / math.sqrt(norm)
    uphi = omega * ut
    u_t = gtt * ut + gtphi * uphi
    u_phi = gtphi * ut + gphph * uphi
    if abs(u_t) < 1e-30:
        raise ValueError("failed to compute specific angular momentum (u_t ~ 0)")
    return -u_phi / u_t


def fm_torus_state(
    r: np.ndarray,
    th: np.ndarray,
    a: float,
    r_in: float,
    r_pmax: float,
    n_poly: float,
) -> Tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray, np.ndarray, np.ndarray, np.ndarray, Dict[str, np.ndarray], float]:
    rr, tt = np.meshgrid(r, th, indexing="ij")
    g = metric_ks_2d(rr, tt, a)

    l_const = circular_l_at_equator(r_pmax, a)

    rin_metric = metric_ks_2d(np.array([[r_in]], dtype=np.float64), np.array([[0.5 * PI]], dtype=np.float64), a)
    gtt_in = float(rin_metric["gtt"][0, 0])
    gtphi_in = float(rin_metric["gtphi"][0, 0])
    gphph_in = float(rin_metric["gphph"][0, 0])
    num_in = gtphi_in * gtphi_in - gtt_in * gphph_in
    den_in = gphph_in + 2.0 * l_const * gtphi_in + (l_const * l_const) * gtt_in
    if num_in <= 0.0 or den_in <= 0.0:
        raise ValueError("invalid inner-edge state for FM torus; adjust r_in/r_max/spin")
    utneg_in = math.sqrt(num_in / den_in)  # -u_t at inner edge

    gtt = g["gtt"]
    gtphi = g["gtphi"]
    gphph = g["gphph"]

    num = gtphi * gtphi - gtt * gphph
    den = gphph + 2.0 * l_const * gtphi + (l_const * l_const) * gtt
    valid = (num > 0.0) & (den > 0.0)
    utneg = np.sqrt(np.maximum(num / np.maximum(den, 1e-30), 1e-30))  # -u_t

    h = utneg_in / np.maximum(utneg, 1e-30)
    torus_mask = valid & (rr >= r_in) & (h > 1.0)

    gamma = 1.0 + 1.0 / n_poly
    k_poly = 1.0
    rho_floor = 1e-12

    hm1 = np.maximum(h - 1.0, 0.0)
    rho = np.where(torus_mask, np.power(hm1 / ((n_poly + 1.0) * k_poly), n_poly), rho_floor)
    p = np.where(torus_mask, k_poly * np.power(np.maximum(rho, rho_floor), gamma), np.power(rho_floor, gamma))

    omega = -(gtphi + l_const * gtt) / np.maximum(gphph + l_const * gtphi, 1e-30)
    norm = -(gtt + 2.0 * gtphi * omega + gphph * omega * omega)
    ut_orbit = 1.0 / np.sqrt(np.maximum(norm, 1e-30))
    ut_static = 1.0 / np.sqrt(np.maximum(-gtt, 1e-30))

    ut = np.where(torus_mask, ut_orbit, ut_static)
    ur = np.zeros_like(ut)
    uth = np.zeros_like(ut)
    uphi = np.where(torus_mask, omega * ut, np.zeros_like(ut))

    return rho, p, ut, ur, uth, uphi, torus_mask, g, l_const


def magnetic_from_vector_potential(
    r: np.ndarray,
    th: np.ndarray,
    g: Dict[str, np.ndarray],
    rho: np.ndarray,
    rho_cut_frac: float,
) -> Tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    rho_max = float(np.max(rho))
    rho_cut = max(rho_cut_frac, 0.0) * rho_max
    aphi = np.maximum(rho - rho_cut, 0.0)

    sqrt_gamma = np.sqrt(np.maximum(g["det_gamma"], 1e-30))
    d_a_dth = finite_diff(aphi, th, axis=1)
    d_a_dr = finite_diff(aphi, r, axis=0)

    br = d_a_dth / np.maximum(sqrt_gamma, 1e-30)
    bth = -d_a_dr / np.maximum(sqrt_gamma, 1e-30)
    bphi = np.zeros_like(br)
    mag_mask = aphi > 0.0
    return aphi, br, bth, bphi, mag_mask


def spatial_b2(g: Dict[str, np.ndarray], br: np.ndarray, bth: np.ndarray, bphi: np.ndarray) -> np.ndarray:
    return (
        g["grr"] * br * br
        + 2.0 * g["grphi"] * br * bphi
        + g["gthth"] * bth * bth
        + g["gphph"] * bphi * bphi
    )


def compute_bcon(
    g: Dict[str, np.ndarray],
    ut: np.ndarray,
    ur: np.ndarray,
    uth: np.ndarray,
    uphi: np.ndarray,
    br: np.ndarray,
    bth: np.ndarray,
    bphi: np.ndarray,
) -> Tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    u_t = g["gtt"] * ut + g["gtr"] * ur + g["gtphi"] * uphi
    u_r = g["gtr"] * ut + g["grr"] * ur + g["grphi"] * uphi
    u_th = g["gthth"] * uth
    u_phi = g["gtphi"] * ut + g["grphi"] * ur + g["gphph"] * uphi

    b0 = br * u_r + bth * u_th + bphi * u_phi
    inv_ut = 1.0 / np.maximum(ut, 1e-30)
    b_r = (br + b0 * ur) * inv_ut
    b_th = (bth + b0 * uth) * inv_ut
    b_phi = (bphi + b0 * uphi) * inv_ut

    b_t_cov = g["gtt"] * b0 + g["gtr"] * b_r + g["gtphi"] * b_phi
    b_r_cov = g["gtr"] * b0 + g["grr"] * b_r + g["grphi"] * b_phi
    b_th_cov = g["gthth"] * b_th
    b_phi_cov = g["gtphi"] * b0 + g["grphi"] * b_r + g["gphph"] * b_phi
    b2 = b0 * b_t_cov + b_r * b_r_cov + b_th * b_th_cov + b_phi * b_phi_cov
    return b0, b_r, b_th, b_phi, b2


def divergence_b(
    r: np.ndarray,
    th: np.ndarray,
    g: Dict[str, np.ndarray],
    br: np.ndarray,
    bth: np.ndarray,
    bphi: np.ndarray,
) -> Tuple[np.ndarray, float, float]:
    # div B = (1/sqrt(gamma)) * d_i( sqrt(gamma) B^i )
    sqrt_gamma = np.sqrt(np.maximum(g["det_gamma"], 1e-30))
    sr = sqrt_gamma * br
    sth = sqrt_gamma * bth

    dsr_dr = finite_diff(sr, r, axis=0)
    dsth_dth = finite_diff(sth, th, axis=1)
    # Axisymmetric A_phi => B_phi ~ 0 and no phi term.
    divb = (dsr_dr + dsth_dth) / np.maximum(sqrt_gamma, 1e-30)

    bmag = np.sqrt(np.maximum(spatial_b2(g, br, bth, bphi), 1e-30))
    dr = float(np.mean(np.diff(r))) if r.size > 1 else 1.0
    dth = float(np.mean(np.diff(th))) if th.size > 1 else 1.0
    rmid = float(np.mean(r))
    lref = max(min(dr, rmid * dth), 1e-8)
    rel_max = float(np.max(np.abs(divb)) * lref / max(float(np.max(bmag)), 1e-30))
    rms = float(np.sqrt(np.mean(divb * divb)))
    return divb, rms, rel_max


def main() -> None:
    ap = argparse.ArgumentParser(description="Build Fishbone-Moncrief torus IC snapshot (Kerr-Schild).")
    ap.add_argument("--output", required=True, help="output .h5 path")
    ap.add_argument("--nr", type=int, default=96, help="radial bins")
    ap.add_argument("--nth", type=int, default=64, help="polar(theta) bins")
    ap.add_argument("--nphi", type=int, default=192, help="azimuth bins")
    ap.add_argument("--r-min", type=float, default=1.45, help="minimum radius (M units)")
    ap.add_argument("--r-max", type=float, default=9.0, help="maximum radius (M units)")
    ap.add_argument("--spin", type=float, default=0.92, help="black-hole spin a in [-0.999, 0.999]")
    ap.add_argument("--r-in", type=float, default=4.5, help="torus inner radius")
    ap.add_argument("--r-max-pressure", type=float, default=6.0, help="pressure maximum radius")
    ap.add_argument("--n-poly", type=float, default=3.0, help="polytropic index n (Gamma=1+1/n)")
    ap.add_argument("--target-beta", type=float, default=100.0, help="target plasma beta p/(B^2/8pi)")
    ap.add_argument("--rho-cut-frac", type=float, default=0.2, help="A_phi cutoff as fraction of rho_max")
    ap.add_argument("--perturb", type=float, default=0.01, help="density perturbation amplitude (e.g. 0.01)")
    ap.add_argument("--seed", type=int, default=1337, help="RNG seed for perturbation")
    ap.add_argument("--sigma-max", type=float, default=1.0, help="global sigma cap b^2/(rho h)")
    args = ap.parse_args()

    if h5py is None:
        raise RuntimeError("h5py is required. install with: python3 -m pip install h5py")
    if args.nr < 8 or args.nth < 8 or args.nphi < 16:
        raise ValueError("nr/nth/nphi are too small (recommended: nr>=8, nth>=8, nphi>=16)")
    if not (args.r_max > args.r_min > 0.0):
        raise ValueError("must satisfy r_max > r_min > 0")
    if not (-0.999 <= args.spin <= 0.999):
        raise ValueError("spin must be in [-0.999, 0.999]")
    if not (args.r_max_pressure > args.r_in > args.r_min):
        raise ValueError("must satisfy r_max_pressure > r_in > r_min")
    if args.n_poly <= 0.0:
        raise ValueError("n-poly must be > 0")
    if args.target_beta <= 0.0:
        raise ValueError("target-beta must be > 0")
    if args.sigma_max <= 0.0:
        raise ValueError("sigma-max must be > 0")
    if args.perturb < 0.0:
        raise ValueError("perturb must be >= 0")

    r_h = kerr_horizon_radius(args.spin)
    if args.r_min <= r_h * 1.01:
        raise ValueError(
            f"r-min={args.r_min:.6f} is too close to/below horizon r_h={r_h:.6f}; use r-min > {r_h*1.01:.6f}"
        )

    # Avoid exactly polar singular points in spherical coordinates.
    th_min = 1e-3
    th_max = PI - 1e-3

    r = np.linspace(args.r_min, args.r_max, args.nr, dtype=np.float64)
    th = np.linspace(th_min, th_max, args.nth, dtype=np.float64)
    phi = np.linspace(0.0, TWOPI, args.nphi, endpoint=False, dtype=np.float64)

    rho2, p2, ut2, ur2, uth2, uphi2, torus_mask2, g2, l_const = fm_torus_state(
        r=r,
        th=th,
        a=args.spin,
        r_in=args.r_in,
        r_pmax=args.r_max_pressure,
        n_poly=args.n_poly,
    )

    aphi2, br2, bth2, bphi2, mag_mask2 = magnetic_from_vector_potential(
        r=r,
        th=th,
        g=g2,
        rho=rho2,
        rho_cut_frac=args.rho_cut_frac,
    )

    b2_spatial = spatial_b2(g2, br2, bth2, bphi2)
    beta_local = p2[mag_mask2] / np.maximum((b2_spatial[mag_mask2] / (8.0 * PI)), 1e-30)
    if beta_local.size == 0:
        raise ValueError("magnetized region is empty; lower --rho-cut-frac or adjust torus geometry")
    beta_current = float(np.exp(np.mean(np.log(np.clip(beta_local, 1e-30, None)))))
    b_scale = math.sqrt(beta_current / args.target_beta)
    br2 *= b_scale
    bth2 *= b_scale
    bphi2 *= b_scale
    aphi2 *= b_scale

    b0_2, b_r_2, b_th_2, b_phi_2, b2_2 = compute_bcon(g2, ut2, ur2, uth2, uphi2, br2, bth2, bphi2)
    h2 = 1.0 + (args.n_poly + 1.0) * (p2 / np.maximum(rho2, 1e-30))
    sigma2 = b2_2 / np.maximum(rho2 * h2, 1e-30)
    sigma_current = float(np.nanmax(sigma2[mag_mask2])) if np.any(mag_mask2) else 0.0
    if sigma_current > args.sigma_max:
        down = math.sqrt(args.sigma_max / max(sigma_current, 1e-30))
        br2 *= down
        bth2 *= down
        bphi2 *= down
        aphi2 *= down
        b_scale *= down
        b0_2, b_r_2, b_th_2, b_phi_2, b2_2 = compute_bcon(g2, ut2, ur2, uth2, uphi2, br2, bth2, bphi2)
        sigma2 = b2_2 / np.maximum(rho2 * h2, 1e-30)
        sigma_current = float(np.nanmax(sigma2[mag_mask2])) if np.any(mag_mask2) else 0.0

    divb2, divb_rms, divb_rel_max = divergence_b(r, th, g2, br2, bth2, bphi2)

    gamma = 1.0 + 1.0 / args.n_poly
    rho_floor = 1e-12
    p_floor = rho_floor ** gamma

    rng = np.random.default_rng(args.seed)
    rho3 = np.repeat(rho2[:, :, None], args.nphi, axis=2)
    p3 = np.repeat(p2[:, :, None], args.nphi, axis=2)
    torus_mask3 = np.repeat(torus_mask2[:, :, None], args.nphi, axis=2)
    if args.perturb > 0.0:
        d = 1.0 + args.perturb * (2.0 * rng.random(size=rho3.shape) - 1.0)
        rho3 = np.where(torus_mask3, np.maximum(rho3 * d, rho_floor), rho3)
        p3 = np.where(torus_mask3, np.maximum(np.power(rho3, gamma), p_floor), p3)

    u_internal3 = p3 / max(gamma - 1.0, 1e-30)
    thetae3 = p3 / np.maximum(rho3, 1e-30)

    rr2, tt2 = np.meshgrid(r, th, indexing="ij")
    omega2 = np.where(ut2 > 0.0, uphi2 / np.maximum(ut2, 1e-30), 0.0)
    vphi2 = np.clip(omega2 * rr2 * np.sin(tt2), -0.999, 0.999)
    vr2 = np.zeros_like(vphi2)
    vz2 = np.zeros_like(vphi2)

    vr3 = np.repeat(vr2[:, :, None], args.nphi, axis=2)
    vphi3 = np.repeat(vphi2[:, :, None], args.nphi, axis=2)
    vz3 = np.repeat(vz2[:, :, None], args.nphi, axis=2)

    br3 = np.repeat(br2[:, :, None], args.nphi, axis=2)
    bth3 = np.repeat(bth2[:, :, None], args.nphi, axis=2)
    bphi3 = np.repeat(bphi2[:, :, None], args.nphi, axis=2)
    bz3 = -bth3

    ut3 = np.repeat(ut2[:, :, None], args.nphi, axis=2)
    ur3 = np.repeat(ur2[:, :, None], args.nphi, axis=2)
    uth3 = np.repeat(uth2[:, :, None], args.nphi, axis=2)
    uphi3 = np.repeat(uphi2[:, :, None], args.nphi, axis=2)

    b0_3 = np.repeat(b0_2[:, :, None], args.nphi, axis=2)
    b_r_3 = np.repeat(b_r_2[:, :, None], args.nphi, axis=2)
    b_th_3 = np.repeat(b_th_2[:, :, None], args.nphi, axis=2)
    b_phi_3 = np.repeat(b_phi_2[:, :, None], args.nphi, axis=2)
    b2_3 = np.repeat(b2_2[:, :, None], args.nphi, axis=2)
    sigma3 = b2_3 / np.maximum(rho3 * (1.0 + (args.n_poly + 1.0) * p3 / np.maximum(rho3, 1e-30)), 1e-30)

    out = Path(args.output).expanduser().resolve()
    out.parent.mkdir(parents=True, exist_ok=True)

    with h5py.File(out, "w") as f:
        # Coordinates
        f.create_dataset("r", data=r.astype(np.float64))
        f.create_dataset("theta", data=th.astype(np.float64))
        f.create_dataset("phi", data=phi.astype(np.float64))
        f.create_dataset("x1v", data=r.astype(np.float64))
        f.create_dataset("x2v", data=th.astype(np.float64))
        f.create_dataset("x3v", data=phi.astype(np.float64))

        # Primitive thermodynamics
        f.create_dataset("rho", data=rho3.astype(np.float32))
        f.create_dataset("density", data=rho3.astype(np.float32))
        f.create_dataset("p", data=p3.astype(np.float32))
        f.create_dataset("press", data=p3.astype(np.float32))
        f.create_dataset("prs", data=p3.astype(np.float32))
        f.create_dataset("u", data=u_internal3.astype(np.float32))
        f.create_dataset("thetae", data=thetae3.astype(np.float32))

        # Renderer-friendly velocity aliases
        f.create_dataset("vr", data=vr3.astype(np.float32))
        f.create_dataset("vphi", data=vphi3.astype(np.float32))
        f.create_dataset("vz", data=vz3.astype(np.float32))
        f.create_dataset("vx1", data=vr3.astype(np.float32))
        f.create_dataset("vx2", data=vz3.astype(np.float32))
        f.create_dataset("vx3", data=vphi3.astype(np.float32))

        # 4-velocity (contravariant)
        ucon = np.stack([ut3, ur3, uth3, uphi3], axis=0).astype(np.float32)
        f.create_dataset("ucon", data=ucon)
        f.create_dataset("u0", data=ut3.astype(np.float32))
        f.create_dataset("u1", data=ur3.astype(np.float32))
        f.create_dataset("u2", data=uth3.astype(np.float32))
        f.create_dataset("u3", data=uphi3.astype(np.float32))

        # Magnetic field (contravariant spatial components)
        f.create_dataset("Br", data=br3.astype(np.float32))
        f.create_dataset("Bphi", data=bphi3.astype(np.float32))
        f.create_dataset("Bz", data=bz3.astype(np.float32))
        f.create_dataset("B1", data=br3.astype(np.float32))
        f.create_dataset("B2", data=bth3.astype(np.float32))
        f.create_dataset("B3", data=bphi3.astype(np.float32))

        # Magnetic 4-vector b^mu and diagnostics
        bcon = np.stack([b0_3, b_r_3, b_th_3, b_phi_3], axis=0).astype(np.float32)
        f.create_dataset("bcon", data=bcon)
        f.create_dataset("b0", data=b0_3.astype(np.float32))
        f.create_dataset("b1", data=b_r_3.astype(np.float32))
        f.create_dataset("b2", data=b_th_3.astype(np.float32))
        f.create_dataset("b3", data=b_phi_3.astype(np.float32))
        f.create_dataset("bsq", data=b2_3.astype(np.float32))
        f.create_dataset("sigma", data=sigma3.astype(np.float32))

        # Axisymmetric diagnostics on (r, theta)
        f.create_dataset("Aphi_axisym", data=aphi2.astype(np.float32))
        f.create_dataset("divB_axisym", data=divb2.astype(np.float32))
        f.create_dataset("torus_mask_axisym", data=torus_mask2.astype(np.uint8))

        f.attrs["ic_model"] = "fishbone_moncrief_kerr_schild"
        f.attrs["code_units"] = "G=c=M=1"
        f.attrs["spin"] = float(args.spin)
        f.attrs["r_horizon"] = float(r_h)
        f.attrs["r_in"] = float(args.r_in)
        f.attrs["r_max_pressure"] = float(args.r_max_pressure)
        f.attrs["l_const"] = float(l_const)
        f.attrs["n_poly"] = float(args.n_poly)
        f.attrs["Gamma"] = float(gamma)
        f.attrs["target_beta"] = float(args.target_beta)
        f.attrs["b_scale_applied"] = float(b_scale)
        f.attrs["rho_cut_frac"] = float(args.rho_cut_frac)
        f.attrs["perturb_amp"] = float(args.perturb)
        f.attrs["perturb_seed"] = int(args.seed)
        f.attrs["sigma_max_target"] = float(args.sigma_max)
        f.attrs["sigma_max_actual"] = float(np.nanmax(sigma3))
        f.attrs["divB_rms_axisym"] = float(divb_rms)
        f.attrs["divB_rel_max_axisym"] = float(divb_rel_max)
        f.attrs["beta_geo_mean_axisym"] = float(
            np.exp(np.mean(np.log(np.clip(p2[mag_mask2] / np.maximum(spatial_b2(g2, br2, bth2, bphi2)[mag_mask2] / (8.0 * PI), 1e-30), 1e-30, None))))
        )

    print(f"saved FM torus HDF5: {out}")
    print(f"shape: nr={args.nr}, nth={args.nth}, nphi={args.nphi}")
    print(
        "params: "
        f"a={args.spin:.6f}, r_h={r_h:.6f}, r_in={args.r_in:.6f}, "
        f"r_pmax={args.r_max_pressure:.6f}, n={args.n_poly:.6f}, beta_target={args.target_beta:.6f}"
    )
    print(
        "diagnostics: "
        f"divB_rms={divb_rms:.3e}, divB_rel_max={divb_rel_max:.3e}, "
        f"sigma_max={float(np.nanmax(sigma3)):.3e}"
    )


if __name__ == "__main__":
    main()

