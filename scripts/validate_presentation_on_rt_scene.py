#!/usr/bin/env python3
"""Render a simple everyday HDR ray-traced scene and apply Metal presentation.

The goal is to validate the observer/presentation layer with a familiar scene,
separate from black-hole/accretion-source physics.  This script intentionally
uses a tiny deterministic CPU ray tracer: room, ceiling area light, metal sphere,
glass sphere, and diffuse plastic sphere. Optional bokeh targets add small
emissive points at known depths for lens/aperture validation; optional color
patches add familiar diffuse hues for human-vision/chroma validation. It writes
the scene as float4 linear32 HDR and feeds that file into the renderer's actual
Metal compose stage.
"""

from __future__ import annotations

import argparse
import json
import math
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Optional, Tuple

import numpy as np
from PIL import Image, ImageDraw


EPS = 1e-4
ROOT = Path(__file__).resolve().parents[1]
RUN_PIPELINE = ROOT / "Blackhole" / "run_pipeline.sh"
GPU_ROOM_RT = ROOT / "scripts" / "generate_room_rt_hdr_gpu.swift"


@dataclass
class Material:
    kind: str
    albedo: np.ndarray
    roughness: float = 0.0
    ior: float = 1.5
    emission: np.ndarray = None

    def __post_init__(self) -> None:
        if self.emission is None:
            self.emission = np.zeros(3, dtype=np.float32)


@dataclass
class Hit:
    t: float
    p: np.ndarray
    n: np.ndarray
    mat: Material


@dataclass
class Sphere:
    center: np.ndarray
    radius: float
    mat: Material

    def intersect(self, ro: np.ndarray, rd: np.ndarray) -> Optional[Hit]:
        oc = ro - self.center
        b = float(np.dot(oc, rd))
        c = float(np.dot(oc, oc) - self.radius * self.radius)
        h = b * b - c
        if h < 0.0:
            return None
        s = math.sqrt(h)
        t = -b - s
        if t < EPS:
            t = -b + s
        if t < EPS:
            return None
        p = ro + rd * t
        n = (p - self.center) / self.radius
        return Hit(t, p, n.astype(np.float32), self.mat)


@dataclass
class Plane:
    p: np.ndarray
    n: np.ndarray
    mat: Material
    bounds: Tuple[Tuple[float, float], Tuple[float, float], str]

    def intersect(self, ro: np.ndarray, rd: np.ndarray) -> Optional[Hit]:
        denom = float(np.dot(self.n, rd))
        if abs(denom) < 1e-6:
            return None
        t = float(np.dot(self.p - ro, self.n) / denom)
        if t < EPS:
            return None
        p = ro + rd * t
        (a0, a1), (b0, b1), axes = self.bounds
        ia = "xyz".index(axes[0])
        ib = "xyz".index(axes[1])
        if p[ia] < a0 or p[ia] > a1 or p[ib] < b0 or p[ib] > b1:
            return None
        return Hit(t, p.astype(np.float32), self.n.astype(np.float32), self.mat)


@dataclass
class AreaLight:
    center: np.ndarray
    ux: np.ndarray
    uz: np.ndarray
    radiance: np.ndarray

    def samples(self) -> List[np.ndarray]:
        pts: List[np.ndarray] = []
        for a in (-0.35, 0.35):
            for b in (-0.35, 0.35):
                pts.append(self.center + a * self.ux + b * self.uz)
        pts.append(self.center)
        return pts


class Scene:
    def __init__(self, bokeh_targets: bool = False, color_chart: bool = False) -> None:
        white = Material("diffuse", np.array([0.78, 0.76, 0.70], dtype=np.float32))
        warm = Material("diffuse", np.array([0.84, 0.72, 0.58], dtype=np.float32))
        cool = Material("diffuse", np.array([0.55, 0.62, 0.76], dtype=np.float32))
        plastic = Material("diffuse", np.array([0.96, 0.22, 0.10], dtype=np.float32))
        metal = Material("metal", np.array([0.92, 0.88, 0.78], dtype=np.float32), roughness=0.035)
        glass = Material("glass", np.array([0.94, 0.98, 1.00], dtype=np.float32), ior=1.48)
        rear_dark = Material("diffuse", np.array([0.05, 0.055, 0.06], dtype=np.float32))
        rear_light = Material("diffuse", np.array([0.96, 0.94, 0.82], dtype=np.float32))
        amber_led = Material("diffuse", np.ones(3, dtype=np.float32), emission=np.array([55.0, 34.0, 13.0], dtype=np.float32))
        blue_led = Material("diffuse", np.ones(3, dtype=np.float32), emission=np.array([12.0, 24.0, 60.0], dtype=np.float32))
        white_led = Material("diffuse", np.ones(3, dtype=np.float32), emission=np.array([62.0, 58.0, 48.0], dtype=np.float32))
        self.light = AreaLight(
            center=np.array([0.0, 1.98, 0.0], dtype=np.float32),
            ux=np.array([0.85, 0.0, 0.0], dtype=np.float32),
            uz=np.array([0.0, 0.0, 0.55], dtype=np.float32),
            radiance=np.array([18.0, 15.4, 11.8], dtype=np.float32),
        )
        light_mat = Material("diffuse", np.ones(3, dtype=np.float32), emission=self.light.radiance)
        self.objects: List[object] = [
            Plane(np.array([0, -1, 0], dtype=np.float32), np.array([0, 1, 0], dtype=np.float32), white, ((-2.2, 2.2), (-3.1, 1.4), "xz")),
            Plane(np.array([0, 2, 0], dtype=np.float32), np.array([0, -1, 0], dtype=np.float32), white, ((-2.2, 2.2), (-3.1, 1.4), "xz")),
            Plane(np.array([0, 0, -3], dtype=np.float32), np.array([0, 0, 1], dtype=np.float32), warm, ((-2.2, 2.2), (-1.0, 2.0), "xy")),
            Plane(np.array([-2.2, 0, 0], dtype=np.float32), np.array([1, 0, 0], dtype=np.float32), cool, ((-3.1, 1.4), (-1.0, 2.0), "zy")),
            Plane(np.array([2.2, 0, 0], dtype=np.float32), np.array([-1, 0, 0], dtype=np.float32), white, ((-3.1, 1.4), (-1.0, 2.0), "zy")),
            Plane(np.array([0, 1.995, 0], dtype=np.float32), np.array([0, -1, 0], dtype=np.float32), light_mat, ((-0.85, 0.85), (-0.55, 0.55), "xz")),
            Sphere(np.array([-0.85, -0.45, -1.75], dtype=np.float32), 0.55, metal),
            Sphere(np.array([0.35, -0.50, -1.45], dtype=np.float32), 0.50, glass),
            Sphere(np.array([1.05, -0.62, -2.10], dtype=np.float32), 0.38, plastic),
            # Rear-wall contrast target behind the glass sphere. It makes
            # back-surface refraction visible in interpreter/camera validation.
            Plane(np.array([0.0, 0.0, -2.985], dtype=np.float32), np.array([0.0, 0.0, 1.0], dtype=np.float32), rear_dark, ((-0.02, 0.38), (-0.76, -0.36), "xy")),
            Plane(np.array([0.0, 0.0, -2.984], dtype=np.float32), np.array([0.0, 0.0, 1.0], dtype=np.float32), rear_light, ((0.38, 0.78), (-0.76, -0.36), "xy")),
            Plane(np.array([0.0, 0.0, -2.983], dtype=np.float32), np.array([0.0, 0.0, 1.0], dtype=np.float32), rear_light, ((-0.02, 0.38), (-0.36, 0.04), "xy")),
            Plane(np.array([0.0, 0.0, -2.982], dtype=np.float32), np.array([0.0, 0.0, 1.0], dtype=np.float32), rear_dark, ((0.38, 0.78), (-0.36, 0.04), "xy")),
        ]
        if bokeh_targets:
            # Small self-luminous spheres at different depths. They deliberately
            # stress the lens presentation by making aperture shape and focus
            # depth visible; they are not source-physics content.
            self.objects.extend([
                Sphere(np.array([-1.25, 0.45, -2.72], dtype=np.float32), 0.045, amber_led),
                Sphere(np.array([-0.78, 0.82, -2.88], dtype=np.float32), 0.038, white_led),
                Sphere(np.array([0.88, 0.52, -2.66], dtype=np.float32), 0.042, blue_led),
                Sphere(np.array([1.35, 0.95, -2.92], dtype=np.float32), 0.035, white_led),
            ])
        if color_chart:
            # Diffuse color patches on the back wall. These are not a texture;
            # they are familiar reflectance samples for validating eye-mode
            # chroma, Purkinje shift, and highlight desaturation.
            chart_mats = [
                Material("diffuse", np.array([0.92, 0.18, 0.12], dtype=np.float32)),
                Material("diffuse", np.array([0.16, 0.72, 0.24], dtype=np.float32)),
                Material("diffuse", np.array([0.14, 0.30, 0.90], dtype=np.float32)),
                Material("diffuse", np.array([0.94, 0.82, 0.18], dtype=np.float32)),
                Material("diffuse", np.array([0.82, 0.20, 0.82], dtype=np.float32)),
                Material("diffuse", np.array([0.18, 0.82, 0.86], dtype=np.float32)),
            ]
            x0, y0 = -1.60, 0.72
            dx, dy = 0.36, 0.28
            for j in range(2):
                for i in range(3):
                    mat = chart_mats[j * 3 + i]
                    cx0 = x0 + i * 0.46
                    cy0 = y0 - j * 0.40
                    self.objects.append(
                        Plane(
                            np.array([0.0, 0.0, -2.985], dtype=np.float32),
                            np.array([0.0, 0.0, 1.0], dtype=np.float32),
                            mat,
                            ((cx0, cx0 + dx), (cy0, cy0 + dy), "xy"),
                        )
                    )

    def intersect(self, ro: np.ndarray, rd: np.ndarray) -> Optional[Hit]:
        best: Optional[Hit] = None
        for obj in self.objects:
            h = obj.intersect(ro, rd)
            if h is not None and (best is None or h.t < best.t):
                best = h
        return best


def normalize(v: np.ndarray) -> np.ndarray:
    return v / max(float(np.linalg.norm(v)), 1e-12)


def reflect(rd: np.ndarray, n: np.ndarray) -> np.ndarray:
    return rd - 2.0 * float(np.dot(rd, n)) * n


def refract(rd: np.ndarray, n: np.ndarray, eta: float) -> Optional[np.ndarray]:
    cosi = -float(np.dot(n, rd))
    sint2 = eta * eta * max(0.0, 1.0 - cosi * cosi)
    if sint2 > 1.0:
        return None
    cost = math.sqrt(max(0.0, 1.0 - sint2))
    return eta * rd + (eta * cosi - cost) * n


def schlick(cosine: float, ior: float) -> float:
    r0 = ((1.0 - ior) / (1.0 + ior)) ** 2
    return r0 + (1.0 - r0) * ((1.0 - cosine) ** 5)


def visible_sky(rd: np.ndarray) -> np.ndarray:
    t = 0.5 * (rd[1] + 1.0)
    return (1.0 - t) * np.array([0.015, 0.018, 0.022], dtype=np.float32) + t * np.array([0.055, 0.070, 0.095], dtype=np.float32)


def direct_light(scene: Scene, hit: Hit) -> np.ndarray:
    out = np.zeros(3, dtype=np.float32)
    if np.max(hit.mat.emission) > 0.0:
        return hit.mat.emission
    for lp in scene.light.samples():
        wi_vec = lp - hit.p
        dist2 = float(np.dot(wi_vec, wi_vec))
        wi = wi_vec / math.sqrt(max(dist2, 1e-12))
        ndotl = max(float(np.dot(hit.n, wi)), 0.0)
        if ndotl <= 0.0:
            continue
        blocker = scene.intersect(hit.p + hit.n * EPS * 8.0, wi)
        if blocker is not None and blocker.t * blocker.t < dist2 - 2e-3:
            continue
        # Area-light solid-angle approximation. This is intentionally simple but
        # radiometric: radiance * projected-area / distance^2 * Lambertian BRDF.
        area = float(np.linalg.norm(np.cross(scene.light.ux, scene.light.uz)))
        light_n = np.array([0.0, -1.0, 0.0], dtype=np.float32)
        lcos = max(float(np.dot(light_n, -wi)), 0.0)
        omega = area * lcos / max(dist2, 1e-6)
        out += scene.light.radiance * ndotl * omega / math.pi
    return out * hit.mat.albedo / max(len(scene.light.samples()), 1)


def trace(scene: Scene, ro: np.ndarray, rd: np.ndarray, depth: int = 0) -> np.ndarray:
    if depth > 4:
        return np.zeros(3, dtype=np.float32)
    hit = scene.intersect(ro, rd)
    if hit is None:
        return visible_sky(rd)
    mat = hit.mat
    if np.max(mat.emission) > 0.0:
        return mat.emission
    base = direct_light(scene, hit)
    if mat.kind == "diffuse":
        return base + 0.025 * mat.albedo
    if mat.kind == "metal":
        rr = normalize(reflect(rd, hit.n))
        return base * 0.20 + mat.albedo * trace(scene, hit.p + hit.n * EPS * 8.0, rr, depth + 1) * 0.86
    if mat.kind == "glass":
        n = hit.n.copy()
        eta_i, eta_t = 1.0, mat.ior
        cosi = -float(np.dot(n, rd))
        entering = cosi > 0.0
        if not entering:
            n = -n
            eta_i, eta_t = eta_t, eta_i
            cosi = -float(np.dot(n, rd))
        eta = eta_i / eta_t
        refr = refract(rd, n, eta)
        fres = schlick(max(cosi, 0.0), mat.ior)
        refl_col = trace(scene, hit.p + n * EPS * 8.0, normalize(reflect(rd, n)), depth + 1)
        if refr is None:
            return refl_col
        refr_col = trace(scene, hit.p - n * EPS * 8.0, normalize(refr), depth + 1)
        # Weak Beer-Lambert tint for a familiar glass-object check.
        tint = np.exp(-np.array([0.015, 0.006, 0.002], dtype=np.float32) * (depth + 1))
        return base * 0.04 + (fres * refl_col + (1.0 - fres) * refr_col * tint) * mat.albedo
    return base


def primary_depth(scene: Scene, ro: np.ndarray, rd: np.ndarray, focus_fallback: float) -> float:
    hit = scene.intersect(ro, rd)
    return focus_fallback if hit is None else float(hit.t)


def render_scene(width: int,
                 height: int,
                 spp: int,
                 focus_depth: float,
                 bokeh_targets: bool,
                 color_chart: bool,
                 depth_mode: str) -> Tuple[np.ndarray, np.ndarray]:
    scene = Scene(bokeh_targets=bokeh_targets, color_chart=color_chart)
    cam_pos = np.array([0.0, 0.40, 3.20], dtype=np.float32)
    target = np.array([0.05, -0.08, -1.50], dtype=np.float32)
    forward = normalize(target - cam_pos)
    right = normalize(np.cross(forward, np.array([0, 1, 0], dtype=np.float32)))
    up = normalize(np.cross(right, forward))
    fov = math.radians(58.0)
    scale = math.tan(fov * 0.5)
    aspect = width / height
    img = np.zeros((height, width, 3), dtype=np.float32)
    depth = np.full((height, width), focus_depth, dtype=np.float32)
    grid = [(0.5, 0.5)] if spp <= 1 else [(0.25, 0.25), (0.75, 0.25), (0.25, 0.75), (0.75, 0.75)]
    for y in range(height):
        for x in range(width):
            col = np.zeros(3, dtype=np.float32)
            dep_samples: List[float] = []
            for ox, oy in grid:
                px = ((x + ox) / width * 2.0 - 1.0) * aspect * scale
                py = (1.0 - (y + oy) / height * 2.0) * scale
                rd = normalize(forward + px * right + py * up)
                col += trace(scene, cam_pos, rd)
                dep_samples.append(primary_depth(scene, cam_pos, rd, focus_depth))
            img[y, x] = col / len(grid)
            if depth_mode == "min":
                # A single depth cannot represent mixed foreground/background
                # radiance.  Min-depth is a foreground-aware approximation that
                # is usually less wrong for compose-stage DOF silhouettes than
                # averaging samples across an object edge.
                depth[y, x] = min(dep_samples)
            elif depth_mode == "max":
                depth[y, x] = max(dep_samples)
            else:
                depth[y, x] = float(sum(dep_samples) / len(dep_samples))
    return img, depth


def aperture_sample(i: int, n: int, blades: int) -> Tuple[float, float]:
    u = (i + 0.5) / max(n, 1)
    theta = i * 2.399963229728653
    r = math.sqrt(u)
    if blades >= 3:
        sector = 2.0 * math.pi / blades
        local = ((theta + 0.5 * sector) % sector) - 0.5 * sector
        edge = math.cos(0.5 * sector) / max(math.cos(local), 1e-4)
        r *= min(max(edge, 0.0), 1.0)
    return r * math.cos(theta), r * math.sin(theta)


def render_scene_thin_lens_reference(width: int,
                                     height: int,
                                     lens_spp: int,
                                     focus_depth: float,
                                     f_number: float,
                                     dof_strength: float,
                                     aperture_blades: int,
                                     bokeh_targets: bool,
                                     color_chart: bool) -> np.ndarray:
    """Slow CPU reference: integrate camera rays over a finite aperture.

    This is not used as a source model. It is a validation target for the Metal
    compose-stage DOF approximation: physically, a focused pixel gathers rays
    from different points on the aperture that converge on the same focus plane.
    """
    scene = Scene(bokeh_targets=bokeh_targets, color_chart=color_chart)
    cam_pos = np.array([0.0, 0.40, 3.20], dtype=np.float32)
    target = np.array([0.05, -0.08, -1.50], dtype=np.float32)
    forward = normalize(target - cam_pos)
    right = normalize(np.cross(forward, np.array([0, 1, 0], dtype=np.float32)))
    up = normalize(np.cross(right, forward))
    fov = math.radians(58.0)
    scale = math.tan(fov * 0.5)
    aspect = width / height
    img = np.zeros((height, width, 3), dtype=np.float32)
    aperture_radius = 0.09 * max(dof_strength, 0.0) / max(f_number, 0.7)
    samples = max(lens_spp, 1)
    for y in range(height):
        for x in range(width):
            px = ((x + 0.5) / width * 2.0 - 1.0) * aspect * scale
            py = (1.0 - (y + 0.5) / height * 2.0) * scale
            rd_center = normalize(forward + px * right + py * up)
            t_focus = focus_depth / max(float(np.dot(rd_center, forward)), 1e-4)
            focus_point = cam_pos + rd_center * t_focus
            col = np.zeros(3, dtype=np.float32)
            for i in range(samples):
                ax, ay = aperture_sample(i, samples, aperture_blades)
                ro = cam_pos + aperture_radius * (ax * right + ay * up)
                rd = normalize(focus_point - ro)
                col += trace(scene, ro.astype(np.float32), rd.astype(np.float32))
            img[y, x] = col / samples
    return img


def auto_exposure(hdr: np.ndarray, target: float = 0.82) -> float:
    y = luminance(hdr)
    active = y[y > 1e-6]
    if active.size == 0:
        return 1.0
    p995 = float(np.percentile(active, 99.5))
    p50 = float(np.percentile(active, 50.0))
    exp_hi = target / max(p995, 1e-6)
    exp_mid = 0.18 / max(p50, 1e-6)
    return min(exp_mid, exp_hi * 4.0)


def luminance(rgb: np.ndarray) -> np.ndarray:
    return rgb[..., 0] * 0.2126 + rgb[..., 1] * 0.7152 + rgb[..., 2] * 0.0722


def tonemap(rgb: np.ndarray, exposure: float) -> np.ndarray:
    x = np.maximum(rgb * exposure, 0.0)
    # Smooth shoulder, close to a display-preview curve rather than a look grade.
    return x / (1.0 + x)


def gaussian_blur_rgb(rgb: np.ndarray, sigma: float) -> np.ndarray:
    if sigma <= 0.0:
        return rgb
    radius = max(1, int(math.ceil(3.0 * sigma)))
    x = np.arange(-radius, radius + 1, dtype=np.float32)
    k = np.exp(-0.5 * (x / sigma) ** 2)
    k /= np.sum(k)
    pad_x = np.pad(rgb, ((0, 0), (radius, radius), (0, 0)), mode="edge")
    tmp = np.zeros_like(rgb)
    for i, w in enumerate(k):
        tmp += w * pad_x[:, i:i + rgb.shape[1], :]
    pad_y = np.pad(tmp, ((radius, radius), (0, 0), (0, 0)), mode="edge")
    out = np.zeros_like(rgb)
    for i, w in enumerate(k):
        out += w * pad_y[i:i + rgb.shape[0], :, :]
    return out


def bright_pass_glare(rgb: np.ndarray, threshold: float, sigma: float, strength: float) -> np.ndarray:
    y = luminance(rgb)
    gate = smoothstep(threshold, min(threshold + 0.18, 1.0), y)
    bright = rgb * gate[..., None]
    return gaussian_blur_rgb(bright, sigma) * strength


def human_eye(rgb_tm: np.ndarray) -> np.ndarray:
    out = np.clip(rgb_tm, 0.0, 1.0)
    y = luminance(out)
    n = 0.70
    sigma = 0.30
    y_n = np.power(np.maximum(y, 0.0), n)
    s_n = sigma ** n
    white_resp = 1.0 / max(1.0 + s_n, 1e-6)
    receptor_y = (y_n / np.maximum(y_n + s_n, 1e-6)) / white_resp
    adapt = 0.42 * smoothstep(0.004, 0.42, y) * (1.0 - 0.40 * smoothstep(0.76, 1.0, y))
    y_adapt = (1.0 - adapt) * y + adapt * np.clip(receptor_y, 0.0, 1.0)
    out = out * (y_adapt[..., None] / np.maximum(y[..., None], 1e-6))
    y = luminance(out)
    photopic = smoothstep(0.022, 0.210, y)
    y_scotopic = out[..., 0] * 0.050 + out[..., 1] * 0.730 + out[..., 2] * 0.220
    rod = y_scotopic[..., None] * np.array([0.72, 0.98, 1.08], dtype=np.float32)
    rod_y = luminance(rod)
    rod *= (y[..., None] / np.maximum(rod_y[..., None], 1e-6)) * (1.0 + 0.16 * (1.0 - photopic[..., None]))
    out = (1.0 - photopic[..., None]) * rod + photopic[..., None] * out
    y = luminance(out)
    bleach = smoothstep(0.54, 0.96, y)
    hunt = (1.0 - smoothstep(0.06, 0.42, y)) * 0.82 + smoothstep(0.06, 0.42, y) * 1.08
    saturation = ((1.0 - photopic) * 0.08 + photopic * 1.00) * hunt * ((1.0 - bleach) + bleach * 0.42)
    out = (1.0 - saturation[..., None]) * y[..., None] + saturation[..., None] * out
    media = smoothstep(0.10, 0.95, y)
    mesopic_blue = 1.0 - photopic
    out *= (1.0 - 0.12 * mesopic_blue[..., None]) + 0.12 * mesopic_blue[..., None] * np.array([0.955, 1.010, 1.085], dtype=np.float32)
    out *= (1.0 - 0.24 * media[..., None]) + 0.24 * media[..., None] * np.array([1.040, 1.000, 0.875], dtype=np.float32)
    y2 = luminance(out)
    out = (1.0 - 0.38 * bleach[..., None]) * out + (0.38 * bleach[..., None]) * y2[..., None]
    # Ocular media scatter: broad, low-strength bright-pass veil.  This is an
    # observer effect and does not alter scene radiance or object geometry.
    out = out + bright_pass_glare(out, threshold=0.33, sigma=3.8, strength=0.055)
    return np.clip(out, 0.0, 1.0)


def smoothstep(a: float, b: float, x: np.ndarray) -> np.ndarray:
    t = np.clip((x - a) / max(b - a, 1e-8), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def cinema(rgb_tm: np.ndarray) -> np.ndarray:
    out = np.clip(rgb_tm, 0.0, 1.0)
    y = luminance(out)
    # Restrained camera response: finite full-well shoulder, mild toe,
    # vignetting, PSF/glare, and deterministic sensor noise. These are sensor
    # effects, not source morphology edits.
    toe = smoothstep(0.00, 0.20, y)
    out = (1.0 - toe[..., None]) * (out * 0.78) + toe[..., None] * out
    shoulder = smoothstep(0.58, 0.98, y)
    well = 1.15 * (1.0 - np.exp(-out / 1.15))
    out = (1.0 - 0.55 * shoulder[..., None]) * out + (0.55 * shoulder[..., None]) * well
    mat = np.array([[1.030, 0.012, -0.010], [0.006, 1.000, 0.004], [-0.006, 0.018, 0.975]], dtype=np.float32)
    out = np.einsum("...c,dc->...d", out, mat)
    y = luminance(out)
    out = y[..., None] + 1.055 * (out - y[..., None])
    yy, xx = np.mgrid[0:out.shape[0], 0:out.shape[1]]
    uvx = (xx + 0.5) / out.shape[1] - 0.5
    uvy = (yy + 0.5) / out.shape[0] - 0.5
    uvx *= out.shape[1] / max(out.shape[0], 1)
    r2 = uvx * uvx + uvy * uvy
    vignette = np.clip(1.0 - 0.42 * r2 - 0.08 * r2 * r2, 0.70, 1.0)
    out *= vignette[..., None]
    out = out + bright_pass_glare(out, threshold=0.30, sigma=1.7, strength=0.035)
    # Deterministic read/shot noise so repeated validation is stable.
    rng = np.random.default_rng(12345)
    y = luminance(out)
    sigma = 0.0022 + 0.0065 * np.sqrt(np.maximum(y, 0.0))
    common = rng.normal(0.0, 1.0, size=y.shape).astype(np.float32)
    chroma = rng.normal(0.0, 1.0, size=out.shape).astype(np.float32)
    out += sigma[..., None] * (0.65 * common[..., None] + 0.35 * chroma)
    return np.clip(out, 0.0, 1.0)


def save_png(path: Path, rgb: np.ndarray) -> None:
    arr = np.clip(rgb, 0.0, 1.0)
    Image.fromarray((arr * 255.0 + 0.5).astype(np.uint8), mode="RGB").save(path)


def image_stats(rgb: np.ndarray) -> Dict[str, float]:
    y = luminance(rgb)
    gy, gx = np.gradient(y)
    grad = np.sqrt(gx * gx + gy * gy)
    mx = np.max(rgb, axis=-1)
    mn = np.min(rgb, axis=-1)
    sat = (mx - mn) / np.maximum(mx, 1e-6)
    blue_green_bias = rgb[..., 2] + 0.5 * rgb[..., 1] - 1.5 * rgb[..., 0]
    return {
        "mean_luma": float(y.mean()),
        "p50_luma": float(np.percentile(y, 50.0)),
        "p90_luma": float(np.percentile(y, 90.0)),
        "p99_luma": float(np.percentile(y, 99.0)),
        "sat_fraction": float(np.mean(np.max(rgb, axis=-1) > 0.995)),
        "grad_p95": float(np.percentile(grad, 95.0)),
        "local_contrast": float(np.std(y) / max(float(np.mean(y)), 1e-8)),
        "mean_saturation": float(np.mean(sat)),
        "p90_saturation": float(np.percentile(sat, 90.0)),
        "mean_blue_green_bias": float(np.mean(blue_green_bias)),
    }


def corr(a: np.ndarray, b: np.ndarray) -> float:
    aa = a.astype(np.float64).reshape(-1)
    bb = b.astype(np.float64).reshape(-1)
    aa -= aa.mean()
    bb -= bb.mean()
    denom = math.sqrt(float(np.dot(aa, aa) * np.dot(bb, bb)))
    return 0.0 if denom < 1e-12 else float(np.dot(aa, bb) / denom)


def make_sheet(items: List[Tuple[str, Path]], out_path: Path) -> None:
    imgs = [(label, Image.open(path).convert("RGB")) for label, path in items]
    w, h = imgs[0][1].size
    label_h = 26
    sheet = Image.new("RGB", (len(imgs) * w, h + label_h), (10, 10, 10))
    draw = ImageDraw.Draw(sheet)
    for i, (label, im) in enumerate(imgs):
        x = i * w
        draw.rectangle([x, 0, x + w, label_h], fill=(18, 18, 18))
        draw.text((x + 8, 6), label, fill=(235, 235, 235))
        sheet.paste(im, (x, label_h))
    sheet.save(out_path)


def write_linear32(path: Path, hdr: np.ndarray, depth: np.ndarray) -> None:
    rgba = np.zeros((hdr.shape[0], hdr.shape[1], 4), dtype=np.float32)
    # Metal compose flips source Y because renderer intermediates are stored in
    # trace-space order. Store bottom-up so the presentation output is upright.
    rgba[..., :3] = np.flipud(np.maximum(hdr, 0.0))
    # w > 1.25 is the compose sentinel for "final linear radiance". w=2+depth
    # additionally gives cinema mode a source-depth proxy for depth of field.
    # Existing alpha=2 files remain valid and are treated as focused/unknown.
    rgba[..., 3] = 2.0 + np.flipud(np.maximum(depth, 0.0))
    path.write_bytes(rgba.tobytes(order="C"))


def run_gpu_room_rt(hdr_path: Path,
                    width: int,
                    height: int,
                    spp: int,
                    aperture_spp: int,
                    focus_depth: float,
                    f_number: float,
                    dof_strength: float,
                    aperture_blades: int,
                    bokeh_targets: bool,
                    color_chart: bool) -> None:
    cmd = [
        "swift", str(GPU_ROOM_RT),
        "--out", str(hdr_path),
        "--width", str(width),
        "--height", str(height),
        "--spp", str(spp),
        "--aperture-spp", str(aperture_spp),
        "--focus-depth", str(focus_depth),
        "--f-number", str(f_number),
        "--dof-strength", str(dof_strength),
        "--aperture-blades", str(aperture_blades),
    ]
    if bokeh_targets:
        cmd.append("--bokeh-targets")
    if color_chart:
        cmd.append("--color-chart")
    print("+", " ".join(cmd), flush=True)
    subprocess.run(cmd, cwd=str(ROOT), check=True)


def run_metal_compose(hdr_path: Path,
                      out_path: Path,
                      width: int,
                      height: int,
                      presentation: str,
                      focus_depth: float,
                      f_number: float,
                      dof_strength: float,
                      aperture_blades: int,
                      exposure: float,
                      no_build: bool) -> None:
    cmd = [
        "bash", str(RUN_PIPELINE),
        "--compose-hdr-in", str(hdr_path),
        "--width", str(width),
        "--height", str(height),
        "--presentation", presentation,
        "--output", str(out_path),
    ]
    if exposure > 0.0:
        cmd += ["--exposure", str(exposure)]
    if presentation == "scientific":
        cmd += ["--look", "linear"]
    if presentation == "cinema":
        cmd += [
            "--camera-focus-depth", str(focus_depth),
            "--camera-f-number", str(f_number),
            "--camera-dof-strength", str(dof_strength),
            "--camera-aperture-blades", str(aperture_blades),
        ]
    if no_build:
        cmd.append("--no-build")
    print("+", " ".join(cmd), flush=True)
    subprocess.run(cmd, cwd=str(ROOT), check=True)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--out-dir", default="/private/tmp/bh_eye_rt_validation")
    ap.add_argument("--width", type=int, default=420)
    ap.add_argument("--height", type=int, default=240)
    ap.add_argument("--spp", type=int, default=1)
    ap.add_argument("--exposure", type=float, default=-1.0, help="negative means auto")
    ap.add_argument("--focus-depth", type=float, default=4.35)
    ap.add_argument("--f-number", type=float, default=2.4)
    ap.add_argument("--dof-strength", type=float, default=1.35)
    ap.add_argument("--aperture-blades", type=int, default=7)
    ap.add_argument("--lens-reference-spp", type=int, default=0, help="optional slow CPU aperture-sampled reference")
    ap.add_argument("--gpu-room-rt", action="store_true", help="generate the room HDR on the GPU instead of the Python CPU tracer")
    ap.add_argument(
        "--depth-mode",
        choices=("min", "mean", "max"),
        default="min",
        help="single-layer depth proxy written to HDR alpha; min is foreground-aware for DOF validation",
    )
    ap.add_argument("--bokeh-targets", action="store_true", help="add small bright depth targets to reveal aperture bokeh shape")
    ap.add_argument("--color-chart", action="store_true", help="add diffuse RGB/CMY wall patches for eye/chroma validation")
    ap.add_argument("--python-presentation", action="store_true", help="use the local Python presentation approximation instead of Metal compose")
    ap.add_argument("--rebuild-each-render", action="store_true", help="do not add --no-build after the first Metal compose")
    args = ap.parse_args()

    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    hdr_path = out_dir / "rt_room.linear32f32"
    if args.gpu_room_rt:
        run_gpu_room_rt(
            hdr_path,
            args.width,
            args.height,
            args.spp,
            0,
            args.focus_depth,
            args.f_number,
            args.dof_strength,
            args.aperture_blades,
            args.bokeh_targets,
            args.color_chart,
        )
    else:
        hdr, depth = render_scene(
            args.width,
            args.height,
            args.spp,
            args.focus_depth,
            args.bokeh_targets,
            args.color_chart,
            args.depth_mode,
        )
        write_linear32(hdr_path, hdr, depth)
    paths = {
        "scientific": out_dir / "rt_room_scientific.png",
        "eye": out_dir / "rt_room_eye.png",
        "cinema": out_dir / "rt_room_cinema.png",
    }
    lens_reference_path: Optional[Path] = None
    if args.python_presentation:
        exposure = auto_exposure(hdr) if args.exposure < 0.0 else args.exposure
        sci = tonemap(hdr, exposure)
        eye = human_eye(sci)
        cine = cinema(sci)
        save_png(paths["scientific"], sci)
        save_png(paths["eye"], eye)
        save_png(paths["cinema"], cine)
        presentation_backend = "python-approx"
    else:
        exposure = args.exposure
        first = True
        for mode in ("scientific", "eye", "cinema"):
            run_metal_compose(
                hdr_path,
                paths[mode],
                args.width,
                args.height,
                mode,
                args.focus_depth,
                args.f_number,
                args.dof_strength,
                args.aperture_blades,
                args.exposure,
                no_build=(not first and not args.rebuild_each_render),
            )
            first = False
        if args.lens_reference_spp > 0:
            lens_hdr_path = out_dir / "rt_room_thin_lens_reference.linear32f32"
            if args.gpu_room_rt:
                run_gpu_room_rt(
                    lens_hdr_path,
                    args.width,
                    args.height,
                    args.spp,
                    args.lens_reference_spp,
                    args.focus_depth,
                    args.f_number,
                    args.dof_strength,
                    args.aperture_blades,
                    args.bokeh_targets,
                    args.color_chart,
                )
            else:
                lens_hdr = render_scene_thin_lens_reference(
                    args.width,
                    args.height,
                    args.lens_reference_spp,
                    args.focus_depth,
                    args.f_number,
                    args.dof_strength,
                    args.aperture_blades,
                    args.bokeh_targets,
                    args.color_chart,
                )
                write_linear32(lens_hdr_path, lens_hdr, np.full((args.height, args.width), args.focus_depth, dtype=np.float32))
            lens_reference_path = out_dir / "rt_room_thin_lens_reference_cinema.png"
            run_metal_compose(
                lens_hdr_path,
                lens_reference_path,
                args.width,
                args.height,
                "cinema",
                args.focus_depth,
                args.f_number,
                0.0,
                args.aperture_blades,
                args.exposure,
                no_build=True,
            )
        presentation_backend = "metal-compose"

    sheet = out_dir / "rt_room_presentation_sheet.png"
    sheet_items = [("scientific", paths["scientific"]), ("eye", paths["eye"]), ("cinema", paths["cinema"])]
    if lens_reference_path is not None:
        sheet_items.append(("thin-lens ref", lens_reference_path))
    make_sheet(sheet_items, sheet)

    sci = np.asarray(Image.open(paths["scientific"]).convert("RGB"), dtype=np.float32) / 255.0
    eye = np.asarray(Image.open(paths["eye"]).convert("RGB"), dtype=np.float32) / 255.0
    cine = np.asarray(Image.open(paths["cinema"]).convert("RGB"), dtype=np.float32) / 255.0
    sci_y = luminance(sci)
    metrics = {
        "scene": "room_area_light_metal_glass_plastic",
        "presentation_backend": presentation_backend,
        "room_rt_backend": "gpu-metal" if args.gpu_room_rt else "python-cpu",
        "width": args.width,
        "height": args.height,
        "spp": args.spp,
        "exposure": exposure,
        "focus_depth": args.focus_depth,
        "depth_mode": args.depth_mode,
        "f_number": args.f_number,
        "dof_strength": args.dof_strength,
        "aperture_blades": args.aperture_blades,
        "lens_reference_spp": args.lens_reference_spp,
        "bokeh_targets": args.bokeh_targets,
        "color_chart": args.color_chart,
        "scientific": image_stats(sci),
        "eye": image_stats(eye),
        "cinema": image_stats(cine),
        "eye_luma_corr_vs_scientific": corr(sci_y, luminance(eye)),
        "cinema_luma_corr_vs_scientific": corr(sci_y, luminance(cine)),
        "eye_rgb_mae_vs_scientific": float(np.mean(np.abs(eye - sci))),
        "cinema_rgb_mae_vs_scientific": float(np.mean(np.abs(cine - sci))),
        "outputs": {k: str(v) for k, v in paths.items()} | {"sheet": str(sheet), "hdr_input": str(hdr_path)},
    }
    if lens_reference_path is not None:
        ref = np.asarray(Image.open(lens_reference_path).convert("RGB"), dtype=np.float32) / 255.0
        ref_y = luminance(ref)
        cine_y = luminance(cine)
        metrics["thin_lens_reference"] = image_stats(ref)
        metrics["cinema_luma_corr_vs_thin_lens_reference"] = corr(cine_y, ref_y)
        metrics["cinema_mae_vs_thin_lens_reference"] = float(np.mean(np.abs(cine - ref)))
        metrics["outputs"]["thin_lens_reference_cinema"] = str(lens_reference_path)
    (out_dir / "metrics.json").write_text(json.dumps(metrics, indent=2, sort_keys=True), encoding="utf-8")
    (out_dir / "summary.md").write_text(
        "# Everyday RT Presentation Validation\n\n"
        "Scene: simple room with ceiling area light, metal sphere, glass sphere, plastic sphere.\n"
        "This validates presentation behavior on familiar radiance before changing black-hole source physics.\n\n"
        f"Sheet: `{sheet}`\n\n"
        "```json\n" + json.dumps(metrics, indent=2, sort_keys=True) + "\n```\n",
        encoding="utf-8",
    )
    print(json.dumps(metrics, indent=2, sort_keys=True))
    print(f"sheet={sheet}")


if __name__ == "__main__":
    main()
