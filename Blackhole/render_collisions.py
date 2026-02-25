import argparse
import json
import os
import struct
import zlib

import numpy as np

C = 299792458.0
G = 6.67430e-11
M_BH = 1.0e35
K = 1.380649e-23
H_PLANCK = 6.62607015e-34
RS = 2.0 * G * M_BH / (C * C)

C1 = 2.0 * H_PLANCK * C * C
C2 = H_PLANCK * C / K

XYZ_TO_RGB = np.array(
    [
        [3.2406, -1.5372, -0.4986],
        [-0.9689, 1.8758, 0.0415],
        [0.0557, -0.2040, 1.0570],
    ],
    dtype=np.float64,
)

LUMA = np.array([0.2126, 0.7152, 0.0722], dtype=np.float64)

COLLISION_DTYPE = np.dtype(
    [
        ("hit", "<u4"),
        ("ct", "<f4"),
        ("T", "<f4"),
        ("_pad0", "V4"),
        ("v_disk", "<f4", (3,)),
        ("_pad1", "V4"),
        ("direct_world", "<f4", (3,)),
        ("_pad2", "V4"),
        ("noise", "<f4"),
        ("_pad3", "V12"),
    ]
)


def cie_xyz_bar(wavelength_nm: np.ndarray):
    lam = wavelength_nm

    t1 = (lam - 442.0) * np.where(lam < 442.0, 0.0624, 0.0374)
    t2 = (lam - 599.8) * np.where(lam < 599.8, 0.0264, 0.0323)
    t3 = (lam - 501.1) * np.where(lam < 501.1, 0.0490, 0.0382)
    x_bar = 0.362 * np.exp(-0.5 * t1 * t1) + 1.056 * np.exp(-0.5 * t2 * t2) - 0.065 * np.exp(-0.5 * t3 * t3)

    t1 = (lam - 568.8) * np.where(lam < 568.8, 0.0213, 0.0247)
    t2 = (lam - 530.9) * np.where(lam < 530.9, 0.0613, 0.0322)
    y_bar = 0.821 * np.exp(-0.5 * t1 * t1) + 0.286 * np.exp(-0.5 * t2 * t2)

    t1 = (lam - 437.0) * np.where(lam < 437.0, 0.0845, 0.0278)
    t2 = (lam - 459.0) * np.where(lam < 459.0, 0.0385, 0.0725)
    z_bar = 1.217 * np.exp(-0.5 * t1 * t1) + 0.681 * np.exp(-0.5 * t2 * t2)

    return np.clip(x_bar, 0.0, None), np.clip(y_bar, 0.0, None), np.clip(z_bar, 0.0, None)


def build_sensitivity(step_nm: float):
    wavelengths_nm = np.arange(380.0, 751.0, step_nm, dtype=np.float64)
    x_bar, y_bar, z_bar = cie_xyz_bar(wavelengths_nm)
    return wavelengths_nm * 1e-9, x_bar, y_bar, z_bar


def planck_lambda(lam_m: np.ndarray, temperature: np.ndarray) -> np.ndarray:
    x = C2 / np.maximum(lam_m * temperature, 1e-30)
    x = np.clip(x, 1e-8, 700.0)
    return C1 / (np.power(lam_m, 5) * np.expm1(x))


def compute_g_factor_schwarzschild(v: np.ndarray, d: np.ndarray):
    v_norm = np.linalg.norm(v, axis=1)
    d_norm = np.linalg.norm(d, axis=1)
    dot = np.einsum("ij,ij->i", v, d)

    beta = np.clip(v_norm / C, 0.0, 0.999999)
    cos_theta = dot / np.maximum(v_norm * d_norm, 1e-30)
    cos_theta = np.clip(cos_theta, -1.0, 1.0)
    gamma = 1.0 / np.sqrt(1.0 - beta * beta)

    delta = 1.0 / np.maximum(gamma * (1.0 - beta * cos_theta), 1e-9)

    r_emit = (G * M_BH) / np.maximum(v_norm * v_norm, 1e-30)
    r_emit = np.maximum(r_emit, RS * 1.0001)

    g_gr = np.sqrt(np.clip(1.0 - RS / r_emit, 1e-8, 1.0))

    g_total = np.clip(delta * g_gr, 1e-4, 1e4)
    return g_total, r_emit


def render_linear_rgb(
    T_emit: np.ndarray,
    v: np.ndarray,
    d: np.ndarray,
    disk_noise: np.ndarray,
    lam_m: np.ndarray,
    x_bar: np.ndarray,
    y_bar: np.ndarray,
    z_bar: np.ndarray,
    inner_edge_mult: float,
    metric: str,
) -> np.ndarray:
    if metric == "kerr":
        # For Kerr runs, Metal encodes exact GR shift in v_disk:
        # v[:, 0] = g_factor, v[:, 1] = emission radius (meters).
        g_total = np.clip(v[:, 0], 1e-4, 1e4)
        r_emit = np.maximum(v[:, 1], RS * 1.0001)
    else:
        g_total, r_emit = compute_g_factor_schwarzschild(v, d)

    T_obs = np.maximum(T_emit * g_total, 1.0)
    spectrum = planck_lambda(lam_m[None, :], T_obs[:, None])
    spectrum *= np.power(g_total[:, None], 3.0)

    r_in = max(inner_edge_mult, 1.0) * RS
    boundary = np.clip(1.0 - np.sqrt(r_in / np.maximum(r_emit, r_in)), 0.0, 1.0)
    mu = np.abs(d[:, 2]) / np.maximum(np.linalg.norm(d, axis=1), 1e-30)
    limb = 0.4 + 0.6 * np.clip(mu, 0.0, 1.0)
    spectrum *= (boundary * limb)[:, None]

    X = spectrum @ x_bar
    Y = spectrum @ y_bar
    Z = spectrum @ z_bar

    xyz = np.stack([X, Y, Z], axis=1)
    rgb = xyz @ XYZ_TO_RGB.T
    rgb = np.clip(rgb, 0.0, None)

    n = np.clip(disk_noise, -1.0, 1.0)
    cloud = np.clip(0.5 + 0.5 * n, 0.0, 1.0)
    density = 0.72 + 0.68 * cloud
    clump = np.power(cloud, 1.8)

    rgb *= density[:, None]
    rgb *= (1.0 + 0.20 * clump[:, None])
    rgb[:, 0] *= (1.0 + 0.06 * clump)
    rgb[:, 2] *= (1.0 - 0.04 * clump)
    return rgb


def synthetic_disk_noise(v: np.ndarray, rcp: float) -> np.ndarray:
    vxy = v[:, :2]
    speed = np.linalg.norm(vxy, axis=1)
    r_emit = (G * M_BH) / np.maximum(speed * speed, 1e-30)
    re = max(rcp, 1.2) * RS
    u = np.clip((r_emit - RS) / max(re - RS, 1e-12), 0.0, 1.0)

    phi = np.arctan2(-vxy[:, 0], vxy[:, 1])
    theta = phi + 1.9 * np.log(np.maximum(r_emit / RS, 1.0))
    cloud = 0.65 * np.sin(18.0 * u + 3.0 * np.cos(theta)) + 0.35 * np.cos(11.0 * theta)
    return np.clip(cloud, -1.0, 1.0)


def aces_tonemap(x: np.ndarray) -> np.ndarray:
    a, b, c, d, e = 2.51, 0.03, 2.43, 0.59, 0.14
    return np.clip((x * (a * x + b)) / (x * (c * x + d) + e), 0.0, 1.0)


def apply_look(rgb: np.ndarray, look: str) -> np.ndarray:
    look = look.lower()
    if look == "interstellar":
        m = np.array(
            [
                [1.08, 0.03, -0.03],
                [0.02, 1.02, -0.01],
                [-0.03, 0.00, 0.90],
            ],
            dtype=np.float64,
        )
        out = np.clip(rgb @ m.T, 0.0, 1.0)
        return np.clip(np.power(out, 0.95), 0.0, 1.0)

    if look == "eht":
        m = np.array(
            [
                [1.30, 0.22, -0.02],
                [0.18, 1.03, -0.07],
                [-0.06, 0.02, 0.52],
            ],
            dtype=np.float64,
        )
        out = np.clip(rgb @ m.T, 0.0, 1.0)
        y = out @ LUMA
        out = 0.75 * out + 0.25 * y[:, None]
        return np.clip(np.power(out, 1.05), 0.0, 1.0)

    return np.clip(rgb, 0.0, 1.0)


def bayer_dither(x: np.ndarray, y: np.ndarray) -> np.ndarray:
    m = np.array(
        [
            [0, 48, 12, 60, 3, 51, 15, 63],
            [32, 16, 44, 28, 35, 19, 47, 31],
            [8, 56, 4, 52, 11, 59, 7, 55],
            [40, 24, 36, 20, 43, 27, 39, 23],
            [2, 50, 14, 62, 1, 49, 13, 61],
            [34, 18, 46, 30, 33, 17, 45, 29],
            [10, 58, 6, 54, 9, 57, 5, 53],
            [42, 26, 38, 22, 41, 25, 37, 21],
        ],
        dtype=np.float64,
    )
    return (m[y & 7, x & 7] + 0.5) / 64.0 - 0.5


def iter_hit_chunks(mem, total, chunk_size):
    for start in range(0, total, chunk_size):
        end = min(start + chunk_size, total)
        chunk = mem[start:end]
        hit_mask = chunk["hit"] != 0
        if not np.any(hit_mask):
            continue
        hit_local = np.nonzero(hit_mask)[0]
        rec = chunk[hit_mask]
        yield start + hit_local, rec


def load_meta(path: str) -> dict:
    if not path:
        return {}
    with open(path, "r", encoding="utf-8") as f:
        meta = json.load(f)
    if not isinstance(meta, dict):
        raise ValueError("meta JSON must be an object")
    print(f"using meta: {path}")
    return meta


def write_ppm(path: str, img: np.ndarray) -> None:
    h, w, _ = img.shape
    with open(path, "wb") as f:
        f.write(f"P6\\n{w} {h}\\n255\\n".encode("ascii"))
        f.write(img.tobytes())


def write_png(path: str, img: np.ndarray) -> None:
    h, w, c = img.shape
    if c != 3:
        raise ValueError("PNG writer expects RGB image")

    rows = [b"\x00" + img[y].tobytes() for y in range(h)]
    raw = b"".join(rows)
    compressed = zlib.compress(raw, level=6)

    def chunk(tag: bytes, payload: bytes) -> bytes:
        crc = zlib.crc32(tag + payload) & 0xFFFFFFFF
        return struct.pack(">I", len(payload)) + tag + payload + struct.pack(">I", crc)

    ihdr = struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)
    png = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", compressed)
        + chunk(b"IEND", b"")
    )
    with open(path, "wb") as f:
        f.write(png)


def save_rgb_image(path: str, img: np.ndarray) -> None:
    ext = os.path.splitext(path)[1].lower()
    if ext in ("", ".png"):
        write_png(path, img)
    elif ext == ".ppm":
        write_ppm(path, img)
    else:
        raise ValueError(f"Unsupported output extension: {ext}. Use .png or .ppm")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--width", type=int, default=None)
    parser.add_argument("--height", type=int, default=None)
    parser.add_argument("--input", type=str, default="collisions.bin")
    parser.add_argument("--meta", type=str, default="")
    parser.add_argument("--output", type=str, default="blackhole_gpu.png")
    parser.add_argument("--chunk", type=int, default=160000)
    parser.add_argument("--spectral-step", type=float, default=5.0)
    parser.add_argument("--exposure", type=float, default=-1.0, help="negative = auto exposure")
    parser.add_argument("--dither", type=float, default=0.75)
    parser.add_argument("--inner-edge-mult", type=float, default=1.4)
    parser.add_argument("--rcp", type=float, default=None)
    parser.add_argument("--look", type=str, default=None)
    args = parser.parse_args()

    meta = load_meta(args.meta) if args.meta else {}

    W = int(args.width if args.width is not None else meta.get("width", 1200))
    H = int(args.height if args.height is not None else meta.get("height", 1200))
    if W <= 0 or H <= 0:
        raise ValueError("width and height must be positive")

    look = args.look if args.look is not None else str(meta.get("preset", "balanced"))
    metric = str(meta.get("metric", "schwarzschild")).lower()
    rcp = float(args.rcp if args.rcp is not None else meta.get("rcp", 6.0))

    if "collisionStride" in meta:
        stride = int(meta["collisionStride"])
        if stride != COLLISION_DTYPE.itemsize:
            raise ValueError(f"Unexpected collision stride in meta: {stride}")

    total = W * H

    actual_size = np.fromfile(args.input, dtype=np.uint8).size
    expected_size = total * COLLISION_DTYPE.itemsize
    if actual_size != expected_size:
        raise ValueError(f"Unexpected collisions size: {actual_size} (expected {expected_size})")

    mem = np.memmap(args.input, dtype=COLLISION_DTYPE, mode="r", shape=(total,))
    lam_m, x_bar, y_bar, z_bar = build_sensitivity(args.spectral_step)

    eps = 1e-12
    lum_samples = []
    for _, rec in iter_hit_chunks(mem, total, args.chunk):
        T = np.maximum(rec["T"].astype(np.float64), 1.0)
        v = rec["v_disk"].astype(np.float64)
        d = rec["direct_world"].astype(np.float64)
        noise = rec["noise"].astype(np.float64)

        if float(np.max(np.abs(noise))) < 1e-6:
            if metric == "kerr":
                noise = np.zeros_like(noise)
            else:
                noise = synthetic_disk_noise(v, rcp)

        rgb_lin = render_linear_rgb(T, v, d, noise, lam_m, x_bar, y_bar, z_bar, args.inner_edge_mult, metric)
        lum = rgb_lin @ LUMA
        stride = max(1, lum.size // 4096)
        lum_samples.append(lum[::stride])

    if not lum_samples:
        exposure = 1.0
    elif args.exposure > 0.0:
        exposure = args.exposure
    else:
        sample = np.concatenate(lum_samples)
        p50 = float(np.percentile(sample, 50.0))
        p99 = float(np.percentile(sample, 99.5))
        target_white = 0.8
        if look.lower() == "interstellar":
            target_white = 0.9
        elif look.lower() == "eht":
            target_white = 0.6
        exposure = target_white / max(p99, eps)
        print(f"lum p50={p50:.6g}, p99.5={p99:.6g}")

    print(f"exposure={exposure:.6g} (auto={args.exposure <= 0.0})")

    img = np.zeros((H, W, 3), dtype=np.uint8)

    for hit_idx, rec in iter_hit_chunks(mem, total, args.chunk):
        T = np.maximum(rec["T"].astype(np.float64), 1.0)
        v = rec["v_disk"].astype(np.float64)
        d = rec["direct_world"].astype(np.float64)
        noise = rec["noise"].astype(np.float64)

        if float(np.max(np.abs(noise))) < 1e-6:
            if metric == "kerr":
                noise = np.zeros_like(noise)
            else:
                noise = synthetic_disk_noise(v, rcp)

        rgb_lin = render_linear_rgb(T, v, d, noise, lam_m, x_bar, y_bar, z_bar, args.inner_edge_mult, metric)
        rgb_exp = rgb_lin * exposure
        lum = rgb_exp @ LUMA
        lum_tm = aces_tonemap(lum)
        scale = lum_tm / np.maximum(lum, 1e-12)
        rgb_tm = rgb_exp * scale[:, None]
        rgb_tm = apply_look(rgb_tm, look)
        rgb_srgb = np.power(np.clip(rgb_tm, 0.0, 1.0), 1.0 / 2.2)

        y = hit_idx // W
        x = hit_idx - y * W

        if args.dither > 0.0:
            dither = bayer_dither(x, y)[:, None] * (args.dither / 255.0)
            rgb_srgb = np.clip(rgb_srgb + dither, 0.0, 1.0)

        rgb8 = np.clip(rgb_srgb * 255.0 + 0.5, 0.0, 255.0).astype(np.uint8)
        img[H - 1 - y, x] = rgb8

    save_rgb_image(args.output, img)
    print(f"Saved {args.output}")


if __name__ == "__main__":
    main()
