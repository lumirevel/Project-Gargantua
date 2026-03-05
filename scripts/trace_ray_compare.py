#!/usr/bin/env python3
import argparse
import csv
import json
import math
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import numpy as np


M_PI = math.pi
C = 299_792_458.0
G = 6.67430e-11
M_BH = 1.0e35
RS = 2.0 * G * M_BH / (C * C)


@dataclass
class TraceConfig:
    preset: str
    width: int
    height: int
    cam_x: float
    cam_y: float
    cam_z: float
    fov: float
    roll: float
    rcp: float
    disk_h: float
    h: float
    max_steps: int
    eps: float
    spin: float
    kerr_substeps: int
    kerr_tol: float
    kerr_escape_mult: float
    kerr_radial_scale: float
    kerr_azimuth_scale: float
    kerr_impact_scale: float
    pixel_x: int
    pixel_y: int


@dataclass
class TraceResult:
    points: np.ndarray
    hit: bool
    hit_step: int
    hit_pos: Optional[np.ndarray]
    states: List[Dict[str, Any]]
    init_state: Dict[str, Any]


def normalize(v: np.ndarray) -> np.ndarray:
    n = np.linalg.norm(v)
    if n <= 1e-30:
        return v.copy()
    return v / n


def cross(a: np.ndarray, b: np.ndarray) -> np.ndarray:
    return np.cross(a, b)


def conv(r: float, theta: float, phi: float) -> np.ndarray:
    return np.array(
        [
            r * math.sin(theta) * math.cos(phi),
            r * math.sin(theta) * math.sin(phi),
            r * math.cos(theta),
        ],
        dtype=np.float64,
    )


def preset_values(name: str) -> Tuple[float, float, float, float, float, float, float, int]:
    p = name.lower()
    if p == "interstellar":
        return (4.8, 0.0, 0.55, 58.0, -18.0, 9.0, 0.08, 1600)
    if p == "eht":
        return (8.4, 0.0, 0.10, 30.0, 0.0, 4.4, 0.20, 2000)
    return (22.0, 0.0, 0.9, 58.0, -18.0, 9.0, 0.01, 1600)


def build_config(args: argparse.Namespace) -> TraceConfig:
    bcx, bcy, bcz, bfov, broll, brcp, bdisk_h, bsteps = preset_values(args.preset)
    width = args.width
    height = args.height
    px = args.pixel_x if args.pixel_x is not None else width // 2
    py = args.pixel_y if args.pixel_y is not None else height // 2
    return TraceConfig(
        preset=args.preset.lower(),
        width=width,
        height=height,
        cam_x=args.cam_x if args.cam_x is not None else bcx,
        cam_y=args.cam_y if args.cam_y is not None else bcy,
        cam_z=args.cam_z if args.cam_z is not None else bcz,
        fov=args.fov if args.fov is not None else bfov,
        roll=args.roll if args.roll is not None else broll,
        rcp=args.rcp if args.rcp is not None else brcp,
        disk_h=args.disk_h if args.disk_h is not None else bdisk_h,
        h=max(1e-7, args.h if args.h is not None else 0.01),
        max_steps=max(1, args.max_steps if args.max_steps is not None else bsteps),
        eps=1e-5,
        spin=max(0.0, min(0.999, args.spin)),
        kerr_substeps=max(1, min(8, args.kerr_substeps)),
        kerr_tol=max(1e-6, args.kerr_tol),
        kerr_escape_mult=max(1.0, args.kerr_escape_mult),
        kerr_radial_scale=max(0.01, args.kerr_radial_scale),
        kerr_azimuth_scale=max(0.01, args.kerr_azimuth_scale),
        kerr_impact_scale=max(0.1, args.kerr_impact_scale),
        pixel_x=px,
        pixel_y=py,
    )


def build_camera_basis(cfg: TraceConfig):
    cam_pos = np.array([RS * cfg.cam_x, RS * cfg.cam_y, RS * cfg.cam_z], dtype=np.float64)
    z = normalize(cam_pos)
    vup = np.array([0.0, 0.0, 1.0], dtype=np.float64)
    plane_x0 = normalize(cross(vup, z))
    plane_y0 = normalize(cross(z, plane_x0))
    roll = math.radians(cfg.roll)
    plane_x = math.cos(roll) * plane_x0 + math.sin(roll) * plane_y0
    plane_y = normalize(cross(z, plane_x))
    d = cfg.width / (2.0 * math.tan(math.radians(cfg.fov) * 0.5))
    return cam_pos, plane_x, plane_y, z, d


def pixel_dir(cfg: TraceConfig, plane_x, plane_y, z, d) -> np.ndarray:
    x = (float(cfg.pixel_x) + 0.5) - float(cfg.width) * 0.5
    y = (float(cfg.pixel_y) + 0.5) - float(cfg.height) * 0.5
    return normalize(x * plane_x + y * plane_y - d * z)


def inside_disk_volume(pos: np.ndarray, rs: float, re: float, he: float) -> bool:
    dxy = math.hypot(pos[0], pos[1])
    return (dxy > rs) and (dxy < re) and (abs(pos[2]) < he)


def segment_enter_disk(p0: np.ndarray, p1: np.ndarray, rs: float, re: float, he: float) -> Optional[float]:
    in0 = inside_disk_volume(p0, rs, re, he)
    in1 = inside_disk_volume(p1, rs, re, he)
    if (not in0) and in1:
        lo = 0.0
        hi = 1.0
        for _ in range(10):
            mid = 0.5 * (lo + hi)
            pm = (1.0 - mid) * p0 + mid * p1
            if inside_disk_volume(pm, rs, re, he):
                hi = mid
            else:
                lo = mid
        return hi

    coarse = 48
    prev_in = in0
    prev_t = 0.0
    for i in range(1, coarse + 1):
        t = float(i) / float(coarse)
        pm = (1.0 - t) * p0 + t * p1
        now_in = inside_disk_volume(pm, rs, re, he)
        if (not prev_in) and now_in:
            lo = prev_t
            hi = t
            for _ in range(10):
                mid = 0.5 * (lo + hi)
                pm2 = (1.0 - mid) * p0 + mid * p1
                if inside_disk_volume(pm2, rs, re, he):
                    hi = mid
                else:
                    lo = mid
            return hi
        prev_in = now_in
        prev_t = t
    return None


def schwarzschild_accel(p: np.ndarray, v: np.ndarray, rs: float) -> np.ndarray:
    r = max(p[1], rs * (1.0 + 1e-5))
    dt = v[0]
    dr = v[1]
    dphi = v[3]

    w = 1.0 - rs / r
    dw = rs / (r * r)

    ddt = -dw / w * dr * dt
    ddr = w * (r * dphi * dphi + dw * (((dr / w) * (dr / w)) - (C * dt) * (C * dt)) * 0.5)
    ddtheta = 0.0
    ddphi = -2.0 * (dr / r) * dphi
    return np.array([ddt, ddr, ddtheta, ddphi], dtype=np.float64)


def rk4_step_schwarzschild(p: np.ndarray, v: np.ndarray, h: float, rs: float):
    k1p = h * v
    k1v = h * schwarzschild_accel(p, v, rs)

    k2p = h * (v + 0.5 * k1v)
    k2v = h * schwarzschild_accel(p + 0.5 * k1p, v + 0.5 * k1v, rs)

    k3p = h * (v + 0.5 * k2v)
    k3v = h * schwarzschild_accel(p + 0.5 * k2p, v + 0.5 * k2v, rs)

    k4p = h * (v + k3v)
    k4v = h * schwarzschild_accel(p + k3p, v + k3v, rs)

    p += (k1p + 2.0 * k2p + 2.0 * k3p + k4p) / 6.0
    v += (k1v + 2.0 * k2v + 2.0 * k3v + k4v) / 6.0

    if p[1] < 0.0:
        p[1] = -p[1]
        p[3] = (p[3] + M_PI) % (2.0 * M_PI)



def kerr_cov_metric(r: float, theta: float, a: float) -> Dict[str, float]:
    rr = max(r, 1e-6)
    th = min(max(theta, 1e-5), M_PI - 1e-5)
    sth = math.sin(th)
    cth = math.cos(th)
    sth2 = max(sth * sth, 1e-10)
    sigma = rr * rr + a * a * cth * cth
    delta = rr * rr - 2.0 * rr + a * a
    rsq_plus_a2 = rr * rr + a * a
    A = rsq_plus_a2 * rsq_plus_a2 - a * a * delta * sth2

    return {
        "gtt": -(1.0 - (2.0 * rr / sigma)),
        "gtphi": -(2.0 * a * rr * sth2 / sigma),
        "gphiphi": A * sth2 / sigma,
        "grr": sigma / max(delta, 1e-10),
        "gthth": sigma,
        "sigma": sigma,
        "delta": delta,
        "A": A,
    }


def kerr_inv_metric(r: float, theta: float, a: float) -> Dict[str, float]:
    rr = max(r, 1e-6)
    th = min(max(theta, 1e-5), M_PI - 1e-5)
    sth = math.sin(th)
    cth = math.cos(th)
    sth2 = max(sth * sth, 1e-10)
    sigma = rr * rr + a * a * cth * cth
    delta = max(rr * rr - 2.0 * rr + a * a, 1e-10)
    rsq_plus_a2 = rr * rr + a * a
    A = rsq_plus_a2 * rsq_plus_a2 - a * a * delta * sth2

    return {
        "gtt": -A / (sigma * delta),
        "gtphi": -(2.0 * a * rr) / (sigma * delta),
        "gphiphi": (delta - a * a * sth2) / (sigma * delta * sth2),
        "grr": delta / sigma,
        "gthth": 1.0 / sigma,
    }


def kerr_null_residual(r: float, theta: float, a: float, p_t: float, p_phi: float, p_r: float, p_theta: float) -> float:
    g = kerr_inv_metric(r, theta, a)
    return (
        g["gtt"] * p_t * p_t
        + 2.0 * g["gtphi"] * p_t * p_phi
        + g["gphiphi"] * p_phi * p_phi
        + g["grr"] * p_r * p_r
        + g["gthth"] * p_theta * p_theta
    )


def kerr_carter_q(theta: float, a: float, E: float, Lz: float, p_theta: float) -> float:
    th = min(max(theta, 1e-5), M_PI - 1e-5)
    c = math.cos(th)
    s = max(math.sin(th), 1e-6)
    return p_theta * p_theta + c * c * (a * a * (1.0 - E * E) + (Lz * Lz) / (s * s))


def kerr_init_hamiltonian(
    cam_pos: np.ndarray,
    ray_dir: np.ndarray,
    spin: float,
    disk_h: float,
    radial_scale: float = 1.0,
    angular_scale: float = 1.0,
):
    mass_len = 0.5 * RS
    cam_r = float(np.linalg.norm(cam_pos))
    if cam_r <= 1e-12:
        return None

    r0 = cam_r / mass_len
    cos_theta0 = max(-1.0, min(1.0, float(cam_pos[2] / cam_r)))
    theta0 = math.acos(cos_theta0)
    phi0 = math.atan2(float(cam_pos[1]), float(cam_pos[0]))

    sin_t = math.sin(theta0)
    cos_t = math.cos(theta0)
    sin_p = math.sin(phi0)
    cos_p = math.cos(phi0)

    e_r = np.array([sin_t * cos_p, sin_t * sin_p, cos_t], dtype=np.float64)
    e_theta = np.array([cos_t * cos_p, cos_t * sin_p, -sin_t], dtype=np.float64)
    e_phi = np.array([-sin_p, cos_p, 0.0], dtype=np.float64)

    n_r = float(np.dot(ray_dir, e_r))
    n_theta = float(np.dot(ray_dir, e_theta))
    n_phi = float(np.dot(ray_dir, e_phi))
    focus_range = 0.50
    thin_blend = max(0.0, min(1.0, (disk_h - 0.02) / 0.06))
    focus_strength = 0.25 * thin_blend
    tangent = math.sqrt(max(n_theta * n_theta + n_phi * n_phi, 1e-12))
    focus = max(0.0, min(1.0, (focus_range - tangent) / focus_range))
    radial_eff = max(radial_scale, 0.01) * (1.0 - focus_strength * focus)
    n_r *= radial_eff
    n_theta *= max(angular_scale, 0.01)
    n_phi *= max(angular_scale, 0.01)
    n_norm = math.sqrt(max(n_r * n_r + n_theta * n_theta + n_phi * n_phi, 1e-16))
    n_r /= n_norm
    n_theta /= n_norm
    n_phi /= n_norm

    cov = kerr_cov_metric(r0, theta0, spin)
    if cov["delta"] <= 1e-8:
        return None

    alpha = math.sqrt(max((cov["sigma"] * cov["delta"]) / max(cov["A"], 1e-12), 1e-12))
    omega = (2.0 * spin * r0) / max(cov["A"], 1e-12)
    sqrt_grr = math.sqrt(max(cov["grr"], 1e-12))
    sqrt_gth = math.sqrt(max(cov["gthth"], 1e-12))
    sqrt_gphi = math.sqrt(max(cov["gphiphi"], 1e-12))

    k_t = 1.0 / alpha
    k_r = n_r / sqrt_grr
    k_theta = n_theta / sqrt_gth
    k_phi = omega * k_t + n_phi / sqrt_gphi

    p_t = cov["gtt"] * k_t + cov["gtphi"] * k_phi
    p_phi = cov["gtphi"] * k_t + cov["gphiphi"] * k_phi
    E = -p_t
    if E <= 1e-8:
        return None

    state = {
        "t": 0.0,
        "r": r0,
        "theta": min(max(theta0, 1e-4), M_PI - 1e-4),
        "phi": phi0,
        "pr": (cov["grr"] * k_r) / E,
        "ptheta": (cov["gthth"] * k_theta) / E,
    }
    Lz = p_phi / E

    inv = kerr_inv_metric(state["r"], state["theta"], spin)
    rest = inv["gtt"] + 2.0 * inv["gtphi"] * (-Lz) + inv["gphiphi"] * Lz * Lz + inv["gthth"] * state["ptheta"] ** 2
    rhs = -rest
    if rhs < -1e-6:
        return None
    rhs = max(rhs, 0.0)
    sgn = 1.0 if state["pr"] >= 0.0 else -1.0
    state["pr"] = sgn * math.sqrt(rhs / max(inv["grr"], 1e-12))

    if not (math.isfinite(state["pr"]) and math.isfinite(state["ptheta"]) and math.isfinite(Lz)):
        return None

    horizon = 1.0 + math.sqrt(max(0.0, 1.0 - spin * spin))
    return state, Lz, horizon


def kerr_rhs_hamiltonian(state: Dict[str, float], spin: float, Lz: float):
    r_eval = max(state["r"], 1e-6)
    th_eval = min(max(state["theta"], 1e-5), M_PI - 1e-5)
    p_t = -1.0
    p_phi = Lz

    g = kerr_inv_metric(r_eval, th_eval, spin)
    dt = g["gtt"] * p_t + g["gtphi"] * p_phi
    dphi = g["gtphi"] * p_t + g["gphiphi"] * p_phi
    dr = g["grr"] * state["pr"]
    dtheta = g["gthth"] * state["ptheta"]

    eps_r = max(1e-4, 1e-4 * max(r_eval, 1.0))
    eps_t = 1e-4

    r_plus = r_eval + eps_r
    r_minus = max(r_eval - eps_r, 1e-6)
    t_plus = min(th_eval + eps_t, M_PI - 1e-5)
    t_minus = max(th_eval - eps_t, 1e-5)

    gr_plus = kerr_inv_metric(r_plus, th_eval, spin)
    gr_minus = kerr_inv_metric(r_minus, th_eval, spin)
    gt_plus = kerr_inv_metric(r_eval, t_plus, spin)
    gt_minus = kerr_inv_metric(r_eval, t_minus, spin)

    inv_r_span = 1.0 / max(r_plus - r_minus, 1e-12)
    inv_t_span = 1.0 / max(t_plus - t_minus, 1e-12)

    dgr = {
        k: (gr_plus[k] - gr_minus[k]) * inv_r_span
        for k in ("gtt", "gtphi", "gphiphi", "grr", "gthth")
    }
    dgt = {
        k: (gt_plus[k] - gt_minus[k]) * inv_t_span
        for k in ("gtt", "gtphi", "gphiphi", "grr", "gthth")
    }

    pr2 = state["pr"] * state["pr"]
    pth2 = state["ptheta"] * state["ptheta"]

    term_r = (
        dgr["gtt"] * p_t * p_t
        + 2.0 * dgr["gtphi"] * p_t * p_phi
        + dgr["gphiphi"] * p_phi * p_phi
        + dgr["grr"] * pr2
        + dgr["gthth"] * pth2
    )
    term_t = (
        dgt["gtt"] * p_t * p_t
        + 2.0 * dgt["gtphi"] * p_t * p_phi
        + dgt["gphiphi"] * p_phi * p_phi
        + dgt["grr"] * pr2
        + dgt["gthth"] * pth2
    )

    dpr = -0.5 * term_r
    dptheta = -0.5 * term_t

    null_res = (
        g["gtt"] * p_t * p_t
        + 2.0 * g["gtphi"] * p_t * p_phi
        + g["gphiphi"] * p_phi * p_phi
        + g["grr"] * pr2
        + g["gthth"] * pth2
    )

    deriv = {
        "t": dt,
        "r": dr,
        "theta": dtheta,
        "phi": dphi,
        "pr": dpr,
        "ptheta": dptheta,
    }
    return deriv, null_res


def state_add(state: Dict[str, float], deriv: Dict[str, float], scale: float) -> Dict[str, float]:
    return {k: state[k] + scale * deriv[k] for k in ("t", "r", "theta", "phi", "pr", "ptheta")}


def kerr_dp45_trial(state: Dict[str, float], h: float, spin: float, Lz: float):
    a21 = 1.0 / 5.0
    a31, a32 = 3.0 / 40.0, 9.0 / 40.0
    a41, a42, a43 = 44.0 / 45.0, -56.0 / 15.0, 32.0 / 9.0
    a51, a52, a53, a54 = 19372.0 / 6561.0, -25360.0 / 2187.0, 64448.0 / 6561.0, -212.0 / 729.0
    a61, a62, a63, a64, a65 = 9017.0 / 3168.0, -355.0 / 33.0, 46732.0 / 5247.0, 49.0 / 176.0, -5103.0 / 18656.0
    a71, a73, a74, a75, a76 = 35.0 / 384.0, 500.0 / 1113.0, 125.0 / 192.0, -2187.0 / 6784.0, 11.0 / 84.0

    b1, b3, b4, b5, b6, b7 = 5179.0 / 57600.0, 7571.0 / 16695.0, 393.0 / 640.0, -92097.0 / 339200.0, 187.0 / 2100.0, 1.0 / 40.0

    k1, _ = kerr_rhs_hamiltonian(state, spin, Lz)

    s2 = state_add(state, k1, h * a21)
    k2, _ = kerr_rhs_hamiltonian(s2, spin, Lz)

    s3 = {k: state[k] + h * (a31 * k1[k] + a32 * k2[k]) for k in state}
    k3, _ = kerr_rhs_hamiltonian(s3, spin, Lz)

    s4 = {k: state[k] + h * (a41 * k1[k] + a42 * k2[k] + a43 * k3[k]) for k in state}
    k4, _ = kerr_rhs_hamiltonian(s4, spin, Lz)

    s5 = {k: state[k] + h * (a51 * k1[k] + a52 * k2[k] + a53 * k3[k] + a54 * k4[k]) for k in state}
    k5, _ = kerr_rhs_hamiltonian(s5, spin, Lz)

    s6 = {
        k: state[k] + h * (a61 * k1[k] + a62 * k2[k] + a63 * k3[k] + a64 * k4[k] + a65 * k5[k])
        for k in state
    }
    k6, _ = kerr_rhs_hamiltonian(s6, spin, Lz)

    y5 = {
        k: state[k] + h * (a71 * k1[k] + a73 * k3[k] + a74 * k4[k] + a75 * k5[k] + a76 * k6[k])
        for k in state
    }
    k7, null7 = kerr_rhs_hamiltonian(y5, spin, Lz)

    y4 = {
        k: state[k] + h * (b1 * k1[k] + b3 * k3[k] + b4 * k4[k] + b5 * k5[k] + b6 * k6[k] + b7 * k7[k])
        for k in state
    }

    errs = []
    for k in ("t", "r", "theta", "phi", "pr", "ptheta"):
        scale = max(1.0, abs(state[k]), abs(y5[k]))
        errs.append(abs(y5[k] - y4[k]) / scale)
    err_norm = max(errs)
    if not math.isfinite(err_norm):
        err_norm = 1e30

    return y5, err_norm, null7


def trace_schwarzschild(cfg: TraceConfig, local: np.ndarray, ray_dir: np.ndarray, new_x: np.ndarray, new_y: np.ndarray, new_z: np.ndarray) -> TraceResult:
    rs = RS
    re = rs * cfg.rcp
    he = rs * cfg.disk_h
    r0 = math.sqrt((RS * cfg.cam_x) ** 2 + (RS * cfg.cam_y) ** 2 + (RS * cfg.cam_z) ** 2)

    p = np.array([0.0, r0, 0.5 * M_PI, 0.0], dtype=np.float64)
    v = np.array([0.1, local[0], 0.0, local[1] / max(r0, 1e-12)], dtype=np.float64)

    points: List[np.ndarray] = []
    states: List[Dict[str, Any]] = []
    has_prev = False
    prev = np.zeros(3, dtype=np.float64)
    hit = False
    hit_step = -1
    hit_pos = None
    horizon = rs * (1.0 + cfg.eps)

    for i in range(cfg.max_steps):
        rk4_step_schwarzschild(p, v, cfg.h, rs)
        local_pos = conv(p[1], p[2], p[3])
        world = local_pos[0] * new_x + local_pos[1] * new_y + local_pos[2] * new_z
        points.append(world.copy())

        states.append(
            {
                "step": i,
                "model": "schwarzschild",
                "x": float(world[0]),
                "y": float(world[1]),
                "z": float(world[2]),
                "t": float(p[0]),
                "r": float(p[1]),
                "theta": float(p[2]),
                "phi": float(p[3]),
                "ut": float(v[0]),
                "ur": float(v[1]),
                "utheta": float(v[2]),
                "uphi": float(v[3]),
                "p_t": math.nan,
                "p_r": math.nan,
                "p_theta": math.nan,
                "p_phi": math.nan,
                "E": math.nan,
                "Lz": math.nan,
                "Q": math.nan,
                "null_residual": math.nan,
                "hit_event": 0,
            }
        )

        if has_prev:
            t_enter = segment_enter_disk(prev, world, rs, re, he)
            if t_enter is not None:
                hit_pos = (1.0 - t_enter) * prev + t_enter * world
                hit = True
                hit_step = i
                states[-1]["hit_event"] = 1
                break

        has_prev = True
        prev = world
        dxy = math.hypot(world[0], world[1])
        if dxy > 3.0 * re:
            break
        if p[1] < horizon:
            break
        if not (math.isfinite(p[0]) and math.isfinite(p[1]) and math.isfinite(p[3])):
            break

    init_state = {
        "t": 0.0,
        "r": float(r0),
        "theta": float(0.5 * M_PI),
        "phi": 0.0,
        "ut": 0.1,
        "ur": float(local[0]),
        "utheta": 0.0,
        "uphi": float(local[1] / max(r0, 1e-12)),
    }

    arr = np.array(points, dtype=np.float64) if points else np.zeros((0, 3), dtype=np.float64)
    return TraceResult(points=arr, hit=hit, hit_step=hit_step, hit_pos=hit_pos, states=states, init_state=init_state)


def trace_kerr(cfg: TraceConfig, cam_pos: np.ndarray, ray_dir: np.ndarray, new_x: np.ndarray, new_y: np.ndarray, new_z: np.ndarray) -> TraceResult:
    rs = RS
    re = rs * cfg.rcp
    he = rs * cfg.disk_h
    mass_len = 0.5 * rs

    points: List[np.ndarray] = []
    states: List[Dict[str, Any]] = []
    has_prev = False
    prev = np.zeros(3, dtype=np.float64)
    hit = False
    hit_step = -1
    hit_pos = None

    init = kerr_init_hamiltonian(
        cam_pos,
        ray_dir,
        cfg.spin,
        cfg.disk_h,
        radial_scale=cfg.kerr_radial_scale,
        angular_scale=cfg.kerr_azimuth_scale,
    )
    if init is None:
        return TraceResult(np.zeros((0, 3), dtype=np.float64), False, -1, None, [], {})
    state, Lz, horizon_geom = init
    angular_scale = max(cfg.kerr_impact_scale, 0.05)
    Lz *= angular_scale
    state["ptheta"] *= angular_scale
    inv0 = kerr_inv_metric(state["r"], state["theta"], cfg.spin)
    rest0 = (
        inv0["gtt"]
        + 2.0 * inv0["gtphi"] * (-Lz)
        + inv0["gphiphi"] * Lz * Lz
        + inv0["gthth"] * state["ptheta"] * state["ptheta"]
    )
    rhs0 = max(-rest0, 0.0)
    state["pr"] = math.copysign(math.sqrt(rhs0 / max(inv0["grr"], 1e-12)), state["pr"])

    h_step = max(cfg.h, 1e-6)
    h_min = max(cfg.h * 0.02, 1e-6)
    h_max = max(cfg.h * 2.0, h_min)
    target_steps = min(cfg.max_steps * cfg.kerr_substeps, 40000)
    accepted = 0
    guard = 0

    while accepted < target_steps and guard < target_steps * 12:
        guard += 1
        trial, err_norm, null_res = kerr_dp45_trial(state, h_step, cfg.spin, Lz)
        if not (
            math.isfinite(err_norm)
            and math.isfinite(trial["r"])
            and math.isfinite(trial["theta"])
            and math.isfinite(trial["phi"])
            and math.isfinite(trial["t"])
        ):
            break

        dr_jump = abs(trial["r"] - state["r"])
        dtheta_jump = abs(trial["theta"] - state["theta"])
        dphi_jump = abs(trial["phi"] - state["phi"])
        r_scale = max(state["r"], 1.0)
        jump_bad = (dr_jump > 0.20 * r_scale) or (dtheta_jump > 0.12) or (dphi_jump > 0.8)
        if jump_bad:
            err_norm = max(err_norm, cfg.kerr_tol * 32.0)

        if err_norm <= cfg.kerr_tol or h_step <= h_min * 1.01:
            prev_state = dict(state)
            h_used = h_step
            state = trial
            accepted += 1

            theta_min = 1e-4
            if state["theta"] < theta_min:
                state["theta"] = theta_min
                state["ptheta"] = abs(state["ptheta"])
            elif state["theta"] > M_PI - theta_min:
                state["theta"] = M_PI - theta_min
                state["ptheta"] = -abs(state["ptheta"])

            state["phi"] = math.fmod(state["phi"], 2.0 * M_PI)
            if state["phi"] < 0.0:
                state["phi"] += 2.0 * M_PI

            ratio = max(err_norm / cfg.kerr_tol, 1e-8)
            grow = min(max(0.9 * pow(ratio, -0.2), 0.25), 2.5)
            h_step = min(max(h_step * grow, h_min), h_max)
            if abs(null_res) > 1e-6:
                h_step = max(h_min, h_step * 0.5)

            radius_m = max(state["r"], 0.0) * mass_len
            world = conv(radius_m, state["theta"], state["phi"])
            points.append(world.copy())

            deriv, nres_eval = kerr_rhs_hamiltonian(state, cfg.spin, Lz)
            q_val = kerr_carter_q(state["theta"], cfg.spin, 1.0, Lz, state["ptheta"])
            states.append(
                {
                    "step": accepted - 1,
                    "model": "kerr",
                    "x": float(world[0]),
                    "y": float(world[1]),
                    "z": float(world[2]),
                    "t": float(state["t"]),
                    "r": float(state["r"]),
                    "theta": float(state["theta"]),
                    "phi": float(state["phi"]),
                    "ut": float(deriv["t"]),
                    "ur": float(deriv["r"]),
                    "utheta": float(deriv["theta"]),
                    "uphi": float(deriv["phi"]),
                    "p_t": -1.0,
                    "p_r": float(state["pr"]),
                    "p_theta": float(state["ptheta"]),
                    "p_phi": float(Lz),
                    "E": 1.0,
                    "Lz": float(Lz),
                    "Q": float(q_val),
                    "null_residual": float(nres_eval),
                    "hit_event": 0,
                }
            )

            if has_prev:
                entered = False
                hit_candidate = None

                # Curved-path guard: split one accepted Kerr segment into two half segments.
                mid_state, _, _ = kerr_dp45_trial(prev_state, 0.5 * h_used, cfg.spin, Lz)
                if (
                    math.isfinite(mid_state["r"])
                    and math.isfinite(mid_state["theta"])
                    and math.isfinite(mid_state["phi"])
                ):
                    mid_theta = min(max(mid_state["theta"], 1e-4), M_PI - 1e-4)
                    mid_phi = math.fmod(mid_state["phi"], 2.0 * M_PI)
                    if mid_phi < 0.0:
                        mid_phi += 2.0 * M_PI
                    mid_world = conv(max(mid_state["r"], 0.0) * mass_len, mid_theta, mid_phi)

                    t_enter = segment_enter_disk(prev, mid_world, rs, re, he)
                    if t_enter is not None:
                        hit_candidate = (1.0 - t_enter) * prev + t_enter * mid_world
                        entered = True
                    else:
                        t_enter = segment_enter_disk(mid_world, world, rs, re, he)
                        if t_enter is not None:
                            hit_candidate = (1.0 - t_enter) * mid_world + t_enter * world
                            entered = True

                if not entered:
                    t_enter = segment_enter_disk(prev, world, rs, re, he)
                    if t_enter is not None:
                        hit_candidate = (1.0 - t_enter) * prev + t_enter * world
                        entered = True

                if entered and hit_candidate is not None:
                    hit_pos = hit_candidate
                    hit = True
                    hit_step = accepted - 1
                    states[-1]["hit_event"] = 1
                    break

            has_prev = True
            prev = world

            dxy = math.hypot(float(world[0]), float(world[1]))
            if dxy > cfg.kerr_escape_mult * re:
                break
            if state["r"] <= horizon_geom * (1.0 + cfg.eps):
                break
        else:
            ratio = max(err_norm / cfg.kerr_tol, 1e-8)
            shrink = min(max(0.9 * pow(ratio, -0.25), 0.1), 0.5)
            h_step = max(h_min, h_step * shrink)

    init_state = {
        "t": float(0.0),
        "r": float(init[0]["r"]),
        "theta": float(init[0]["theta"]),
        "phi": float(init[0]["phi"]),
        "p_t": -1.0,
        "p_r": float(init[0]["pr"]),
        "p_theta": float(init[0]["ptheta"]),
        "p_phi": float(Lz),
        "E": 1.0,
        "Lz": float(Lz),
        "Q": float(kerr_carter_q(init[0]["theta"], cfg.spin, 1.0, Lz, init[0]["ptheta"])),
    }

    arr = np.array(points, dtype=np.float64) if points else np.zeros((0, 3), dtype=np.float64)
    return TraceResult(arr, hit, hit_step, hit_pos, states, init_state)


def summarize_dist(s_points: np.ndarray, k_points: np.ndarray):
    n = min(len(s_points), len(k_points))
    if n == 0:
        return n, None
    d = np.linalg.norm(s_points[:n] - k_points[:n], axis=1)
    return n, {
        "p50": float(np.percentile(d, 50.0)),
        "p90": float(np.percentile(d, 90.0)),
        "p99": float(np.percentile(d, 99.0)),
        "max": float(np.max(d)),
        "mean": float(np.mean(d)),
        "dist_array": d,
    }


def write_pair_csv(path: str, s_points: np.ndarray, k_points: np.ndarray):
    n = max(len(s_points), len(k_points))
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["step", "sx", "sy", "sz", "kx", "ky", "kz", "dist"])
        for i in range(n):
            s = s_points[i] if i < len(s_points) else np.array([math.nan, math.nan, math.nan], dtype=np.float64)
            k = k_points[i] if i < len(k_points) else np.array([math.nan, math.nan, math.nan], dtype=np.float64)
            dist = float(np.linalg.norm(s - k)) if (i < len(s_points) and i < len(k_points)) else math.nan
            w.writerow([i, s[0], s[1], s[2], k[0], k[1], k[2], dist])


def write_full_state_csv(path: str, rows: List[Dict[str, Any]]):
    cols = [
        "step",
        "model",
        "x",
        "y",
        "z",
        "t",
        "r",
        "theta",
        "phi",
        "ut",
        "ur",
        "utheta",
        "uphi",
        "p_t",
        "p_r",
        "p_theta",
        "p_phi",
        "E",
        "Lz",
        "Q",
        "null_residual",
        "hit_event",
    ]
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=cols)
        w.writeheader()
        for row in rows:
            w.writerow({k: row.get(k, math.nan) for k in cols})


def build_analysis(
    cfg: TraceConfig,
    s: TraceResult,
    k: TraceResult,
    stats: Optional[Dict[str, Any]],
    max_step_payload: Optional[Dict[str, Any]],
) -> Dict[str, Any]:
    thresholds = [5e6, 1e7, 2e7, 5e7, 1e8, 2e8]
    crossings = []
    if stats is not None:
        dist = stats["dist_array"]
        for th in thresholds:
            idx = np.where(dist >= th)[0]
            first_step = int(idx[0]) if idx.size > 0 else None
            crossings.append({"threshold_m": float(th), "first_step": first_step})

    divergence_stage = "unknown"
    if crossings and crossings[0]["first_step"] is not None:
        first = crossings[0]["first_step"]
        if first <= 5:
            divergence_stage = "initial_mapping"
        elif first <= 40:
            divergence_stage = "early_integration"
        else:
            divergence_stage = "late_integration"

    summary: Dict[str, Any] = {
        "sch_steps": int(len(s.points)),
        "kerr_steps": int(len(k.points)),
        "compared_steps": int(min(len(s.points), len(k.points))),
        "sch_hit": bool(s.hit),
        "kerr_hit": bool(k.hit),
        "hit_match": bool(s.hit == k.hit),
        "divergence_stage": divergence_stage,
    }
    if stats is not None:
        summary.update(
            {
                "dist_p50_m": float(stats["p50"]),
                "dist_p90_m": float(stats["p90"]),
                "dist_p99_m": float(stats["p99"]),
                "dist_mean_m": float(stats["mean"]),
                "dist_max_m": float(stats["max"]),
            }
        )

    return {
        "pixel": {"x": cfg.pixel_x, "y": cfg.pixel_y},
        "preset": cfg.preset,
        "spin": cfg.spin,
        "kerr_params": {
            "substeps": cfg.kerr_substeps,
            "tol": cfg.kerr_tol,
            "escape_mult": cfg.kerr_escape_mult,
            "radial_scale": cfg.kerr_radial_scale,
            "azimuth_scale": cfg.kerr_azimuth_scale,
            "impact_scale": cfg.kerr_impact_scale,
        },
        "summary": summary,
        "threshold_crossings": crossings,
        "init_state": {"schwarzschild": s.init_state, "kerr": k.init_state},
        "max_step_payload": max_step_payload,
    }


def infer_output_paths(csv_path: str, full_state_csv: str, analysis_json: str) -> Tuple[str, str, str]:
    csv_out = csv_path
    if full_state_csv:
        full_out = full_state_csv
    else:
        stem = str(Path(csv_out).with_suffix(""))
        full_out = stem + "_full_state.csv"

    if analysis_json:
        analysis_out = analysis_json
    else:
        stem = str(Path(csv_out).with_suffix(""))
        analysis_out = stem + "_analysis.json"
    return csv_out, full_out, analysis_out


def main():
    parser = argparse.ArgumentParser(description="Trace one ray in Schwarzschild vs Kerr and compare trajectories.")
    parser.add_argument("--preset", type=str, default="interstellar")
    parser.add_argument("--width", type=int, default=1200)
    parser.add_argument("--height", type=int, default=1200)
    parser.add_argument("--pixel-x", type=int, default=None)
    parser.add_argument("--pixel-y", type=int, default=None)
    parser.add_argument("--spin", type=float, default=0.0)
    parser.add_argument("--cam-x", type=float, default=None)
    parser.add_argument("--cam-y", type=float, default=None)
    parser.add_argument("--cam-z", type=float, default=None)
    parser.add_argument("--fov", type=float, default=None)
    parser.add_argument("--roll", type=float, default=None)
    parser.add_argument("--rcp", type=float, default=None)
    parser.add_argument("--disk-h", type=float, default=None)
    parser.add_argument("--h", type=float, default=None)
    parser.add_argument("--max-steps", type=int, default=None)

    parser.add_argument("--kerr-substeps", type=int, default=2)
    parser.add_argument("--kerr-tol", type=float, default=1e-5)
    parser.add_argument("--kerr-escape-mult", type=float, default=3.0)
    parser.add_argument("--kerr-radial-scale", type=float, default=0.67)
    parser.add_argument("--kerr-azimuth-scale", type=float, default=0.92)
    parser.add_argument("--kerr-impact-scale", type=float, default=0.97)

    parser.add_argument("--csv", type=str, default="/tmp/ray_compare.csv")
    parser.add_argument("--full-state-csv", type=str, default="")
    parser.add_argument("--analysis-json", type=str, default="")
    args = parser.parse_args()

    cfg = build_config(args)
    csv_out, full_state_out, analysis_out = infer_output_paths(args.csv, args.full_state_csv, args.analysis_json)

    cam_pos, plane_x, plane_y, z, d = build_camera_basis(cfg)
    ray_dir = pixel_dir(cfg, plane_x, plane_y, z, d)

    new_x = normalize(cam_pos)
    new_z = normalize(cross(new_x, ray_dir))
    new_y = cross(new_z, new_x)
    local = C * np.array([np.dot(new_x, ray_dir), np.dot(new_y, ray_dir), np.dot(new_z, ray_dir)], dtype=np.float64)

    s = trace_schwarzschild(cfg, local, ray_dir, new_x, new_y, new_z)
    k = trace_kerr(cfg, cam_pos, ray_dir, new_x, new_y, new_z)

    n, stats = summarize_dist(s.points, k.points)
    max_payload = None
    if stats is not None and n > 0:
        d = stats["dist_array"]
        idx = int(np.argmax(d))
        max_payload = {
            "step": idx,
            "dist_m": float(d[idx]),
            "schwarz_point": s.points[idx].tolist() if idx < len(s.points) else None,
            "kerr_point": k.points[idx].tolist() if idx < len(k.points) else None,
        }

    write_pair_csv(csv_out, s.points, k.points)
    write_full_state_csv(full_state_out, s.states + k.states)

    analysis = build_analysis(cfg, s, k, stats, max_payload)
    Path(analysis_out).parent.mkdir(parents=True, exist_ok=True)
    with open(analysis_out, "w", encoding="utf-8") as f:
        json.dump(analysis, f, indent=2, sort_keys=True)

    print(
        f"pixel=({cfg.pixel_x},{cfg.pixel_y}), preset={cfg.preset}, spin={cfg.spin}, "
        f"kerrTol={cfg.kerr_tol}, "
        f"kerrScale=({cfg.kerr_radial_scale},{cfg.kerr_azimuth_scale},{cfg.kerr_impact_scale})"
    )
    print(f"steps: schwarzschild={len(s.points)}, kerr={len(k.points)}, compared={n}")
    print(f"hit: schwarzschild={s.hit} step={s.hit_step}, kerr={k.hit} step={k.hit_step}")
    if s.hit_pos is not None:
        print(f"schwarz_hit_pos=({s.hit_pos[0]:.6e}, {s.hit_pos[1]:.6e}, {s.hit_pos[2]:.6e})")
    if k.hit_pos is not None:
        print(f"kerr_hit_pos=({k.hit_pos[0]:.6e}, {k.hit_pos[1]:.6e}, {k.hit_pos[2]:.6e})")
    if stats is not None:
        print(
            "dist(m): "
            f"p50={stats['p50']:.6e}, p90={stats['p90']:.6e}, p99={stats['p99']:.6e}, "
            f"mean={stats['mean']:.6e}, max={stats['max']:.6e}"
        )

    print(f"csv={csv_out}")
    print(f"full_state_csv={full_state_out}")
    print(f"analysis_json={analysis_out}")


if __name__ == "__main__":
    main()
