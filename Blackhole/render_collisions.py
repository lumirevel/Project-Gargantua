import argparse
from datetime import datetime
import json
import os
import struct
import time
from typing import Optional
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
    spectral_encoding: str,
) -> np.ndarray:
    # Metal encodes exact GR shift in v_disk for both metrics:
    # v[:, 0] = g_factor, v[:, 1] = emission radius (meters).
    # Keep this path authoritative to avoid mixing incompatible legacy approximations.
    if spectral_encoding != "gfactor_v1":
        print(
            f"warn: spectralEncoding={spectral_encoding!r} is legacy; using Metal-encoded g-factor path anyway.",
            flush=True,
        )
    g_total = np.clip(v[:, 0], 1e-4, 1e4)
    r_emit = np.maximum(v[:, 1], RS * 1.0001)

    T_obs = np.maximum(T_emit * g_total, 1.0)
    spectrum = planck_lambda(lam_m[None, :], T_obs[:, None])
    spectrum *= np.power(g_total[:, None], 3.0)

    r_in = max(inner_edge_mult, 1.0) * RS
    boundary = np.clip(1.0 - np.sqrt(r_in / np.maximum(r_emit, r_in)), 0.0, 1.0)
    mu = np.abs(d[:, 2]) / np.maximum(np.linalg.norm(d, axis=1), 1e-30)
    # Scattering-dominated accretion-disk atmosphere approximation:
    # I(mu) ~ (3/7) * (1 + 2 mu)
    limb = (3.0 / 7.0) * (1.0 + 2.0 * np.clip(mu, 0.0, 1.0))
    spectrum *= (boundary * limb)[:, None]

    X = spectrum @ x_bar
    Y = spectrum @ y_bar
    Z = spectrum @ z_bar

    xyz = np.stack([X, Y, Z], axis=1)
    rgb = xyz @ XYZ_TO_RGB.T
    rgb = np.clip(rgb, 0.0, None)

    n = np.clip(disk_noise, -1.0, 1.0)
    if float(np.min(n)) < -1e-6:
        cloud = np.clip(0.5 + 0.5 * n, 0.0, 1.0)
    else:
        cloud = np.clip(n, 0.0, 1.0)

    q10, q90 = np.quantile(cloud, [0.08, 0.92])
    span = max(float(q90 - q10), 1e-6)
    cloud = np.clip((cloud - q10) / span, 0.0, 1.0)

    # Reduce sparsity: keep a soft density floor before clump shaping.
    cloud = 0.18 + 0.82 * cloud
    core = np.power(cloud, 1.15)
    clump = np.power(core, 2.2)
    void = np.power(1.0 - cloud, 1.8)
    density = 0.62 + 1.28 * core

    rgb *= density[:, None]
    rgb *= (1.0 + 0.34 * clump[:, None])
    rgb *= (1.0 - 0.14 * void[:, None])
    rgb[:, 0] *= (1.0 + 0.12 * clump)
    rgb[:, 2] *= (1.0 - 0.08 * clump)
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
        f.write(f"P6\n{w} {h}\n255\n".encode("ascii"))
        f.write(img.tobytes())


def build_png_exif_payload(render_conditions: dict) -> bytes:
    comment_text = json.dumps(render_conditions, ensure_ascii=False, separators=(",", ":"), sort_keys=True)
    comment_data = comment_text.encode("utf-8")
    if len(comment_data) > 32000:
        comment_data = comment_data[:32000]
    user_comment = b"ASCII\x00\x00\x00" + comment_data + b"\x00"

    software = b"Blackhole/render_collisions.py\x00"
    date_time = datetime.now().strftime("%Y:%m:%d %H:%M:%S").encode("ascii") + b"\x00"

    ifd0_offset = 8
    ifd0_count = 3
    ifd0_size = 2 + ifd0_count * 12 + 4
    software_offset = ifd0_offset + ifd0_size
    datetime_offset = software_offset + len(software)
    exif_ifd_offset = datetime_offset + len(date_time)

    exif_ifd_count = 1
    exif_ifd_size = 2 + exif_ifd_count * 12 + 4
    comment_offset = exif_ifd_offset + exif_ifd_size

    tiff = bytearray()
    tiff += b"II"
    tiff += struct.pack("<H", 42)
    tiff += struct.pack("<I", ifd0_offset)
    tiff += struct.pack("<H", ifd0_count)
    tiff += struct.pack("<HHII", 0x0131, 2, len(software), software_offset)   # Software
    tiff += struct.pack("<HHII", 0x0132, 2, len(date_time), datetime_offset)   # DateTime
    tiff += struct.pack("<HHII", 0x8769, 4, 1, exif_ifd_offset)                # ExifIFDPointer
    tiff += struct.pack("<I", 0)
    tiff += software
    tiff += date_time
    tiff += struct.pack("<H", exif_ifd_count)
    tiff += struct.pack("<HHII", 0x9286, 7, len(user_comment), comment_offset)  # UserComment
    tiff += struct.pack("<I", 0)
    tiff += user_comment
    return bytes(tiff)


def build_png_itxt_payload(keyword: str, text: str) -> bytes:
    key = keyword.encode("latin-1", errors="replace")[:79]
    if not key:
        key = b"Comment"
    txt = text.encode("utf-8")
    # iTXt: keyword\0 compression_flag compression_method language_tag\0 translated_keyword\0 text
    return key + b"\x00\x00\x00\x00\x00" + txt


def build_png_text_payload(keyword: str, text: str) -> bytes:
    key = keyword.encode("latin-1", errors="replace")[:79]
    if not key:
        key = b"Comment"
    value = text.encode("latin-1", errors="replace")
    return key + b"\x00" + value


def write_png(
    path: str,
    img: np.ndarray,
    exif_payload: Optional[bytes] = None,
    itxt_payload: Optional[bytes] = None,
    text_payload: Optional[bytes] = None,
) -> None:
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
        + (chunk(b"eXIf", exif_payload) if exif_payload else b"")
        + (chunk(b"iTXt", itxt_payload) if itxt_payload else b"")
        + (chunk(b"tEXt", text_payload) if text_payload else b"")
        + chunk(b"IDAT", compressed)
        + chunk(b"IEND", b"")
    )
    with open(path, "wb") as f:
        f.write(png)


def save_rgb_image(
    path: str,
    img: np.ndarray,
    exif_payload: Optional[bytes] = None,
    itxt_payload: Optional[bytes] = None,
    text_payload: Optional[bytes] = None,
) -> None:
    ext = os.path.splitext(path)[1].lower()
    if ext in ("", ".png"):
        write_png(
            path,
            img,
            exif_payload=exif_payload,
            itxt_payload=itxt_payload,
            text_payload=text_payload,
        )
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
    parser.add_argument("--downsample", type=int, default=1, help="box downsample factor for SSAA output (1, 2, 4)")
    parser.add_argument(
        "--exposure-samples",
        type=int,
        default=200000,
        help="max sampled hit pixels used for auto-exposure (0 = legacy full-hit pass)",
    )
    args = parser.parse_args()

    meta = load_meta(args.meta) if args.meta else {}

    W = int(args.width if args.width is not None else meta.get("width", 1200))
    H = int(args.height if args.height is not None else meta.get("height", 1200))
    if W <= 0 or H <= 0:
        raise ValueError("width and height must be positive")
    if args.downsample not in (1, 2, 4):
        raise ValueError("--downsample must be one of 1, 2, 4")
    if (W % args.downsample) != 0 or (H % args.downsample) != 0:
        raise ValueError("width/height must be divisible by --downsample")

    look = args.look if args.look is not None else str(meta.get("preset", "balanced"))
    metric = str(meta.get("metric", "schwarzschild")).lower()
    spectral_encoding = str(meta.get("spectralEncoding", "legacy_vectors")).lower()
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
    progress_last_t = 0.0

    def emit_progress(done_ops: int, total_ops: int, phase: str, task: str = "", force: bool = False) -> None:
        nonlocal progress_last_t
        now = time.monotonic()
        if not force and (now - progress_last_t) < 0.35:
            return
        progress_last_t = now
        extra = f" task={task}" if task else ""
        print(f"ETA_PROGRESS {int(done_ops)} {int(max(total_ops, 1))} {phase}{extra}", flush=True)

    eps = 1e-12
    lum_samples = []
    sample_hits = 0
    hit_total = 0
    if args.exposure <= 0.0:
        if args.exposure_samples < 0:
            raise ValueError("--exposure-samples must be >= 0")
        sample_stride = max(1, total // max(1, args.exposure_samples)) if args.exposure_samples > 0 else 1
        for hit_idx, rec in iter_hit_chunks(mem, total, args.chunk):
            hit_total += int(rec.shape[0])
            rec_sel = rec
            if args.exposure_samples > 0:
                sel = (hit_idx % sample_stride) == 0
                if not np.any(sel):
                    continue
                rec_sel = rec[sel]

            T = np.maximum(rec_sel["T"].astype(np.float64), 1.0)
            v = rec_sel["v_disk"].astype(np.float64)
            d = rec_sel["direct_world"].astype(np.float64)
            noise = rec_sel["noise"].astype(np.float64)

            if float(np.max(np.abs(noise))) < 1e-6:
                if spectral_encoding == "gfactor_v1":
                    noise = np.zeros_like(noise)
                else:
                    noise = synthetic_disk_noise(v, rcp)

            rgb_lin = render_linear_rgb(
                T,
                v,
                d,
                noise,
                lam_m,
                x_bar,
                y_bar,
                z_bar,
                args.inner_edge_mult,
                metric,
                spectral_encoding,
            )
            lum = rgb_lin @ LUMA
            # Keep memory bounded even in full-pass mode.
            stride = max(1, lum.size // 8192)
            s = lum[::stride]
            lum_samples.append(s)
            sample_hits += s.size

    if args.exposure > 0.0:
        for start in range(0, total, args.chunk):
            end = min(start + args.chunk, total)
            hit_total += int(np.count_nonzero(mem[start:end]["hit"] != 0))

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
        print(f"lum p50={p50:.6g}, p99.5={p99:.6g}, exposureSamples={sample_hits}")

    print(f"exposure={exposure:.6g} (auto={args.exposure <= 0.0})")

    ds = args.downsample
    if ds == 1:
        img = np.zeros((H, W, 3), dtype=np.uint8)
        accum = None
        out_h, out_w = H, W
    else:
        out_h = H // ds
        out_w = W // ds
        # Stream SSAA accumulation directly into output resolution to avoid huge high-res buffers.
        accum = np.zeros((out_h, out_w, 3), dtype=np.float32)
        img = None

    first_pass_ops = sample_hits if args.exposure <= 0.0 else 0
    total_ops = first_pass_ops + hit_total
    done_ops = first_pass_ops
    emit_progress(done_ops, total_ops, "python_compose", task="compose", force=True)
    processed_hits = 0

    for hit_idx, rec in iter_hit_chunks(mem, total, args.chunk):
        T = np.maximum(rec["T"].astype(np.float64), 1.0)
        v = rec["v_disk"].astype(np.float64)
        d = rec["direct_world"].astype(np.float64)
        noise = rec["noise"].astype(np.float64)

        if float(np.max(np.abs(noise))) < 1e-6:
            if spectral_encoding == "gfactor_v1":
                noise = np.zeros_like(noise)
            else:
                noise = synthetic_disk_noise(v, rcp)

        rgb_lin = render_linear_rgb(T, v, d, noise, lam_m, x_bar, y_bar, z_bar, args.inner_edge_mult, metric, spectral_encoding)
        rgb_exp = rgb_lin * exposure
        lum = rgb_exp @ LUMA
        lum_tm = aces_tonemap(lum)
        scale = lum_tm / np.maximum(lum, 1e-12)
        rgb_tm = rgb_exp * scale[:, None]
        rgb_tm = apply_look(rgb_tm, look)
        rgb_srgb = np.power(np.clip(rgb_tm, 0.0, 1.0), 1.0 / 2.2)

        y = hit_idx // W
        x = hit_idx - y * W

        if args.dither > 0.0 and ds == 1:
            dither = bayer_dither(x, y)[:, None] * (args.dither / 255.0)
            rgb_srgb = np.clip(rgb_srgb + dither, 0.0, 1.0)

        if ds == 1:
            rgb8 = np.clip(rgb_srgb * 255.0 + 0.5, 0.0, 255.0).astype(np.uint8)
            img[H - 1 - y, x] = rgb8
        else:
            y_out = (H - 1 - y) // ds
            x_out = x // ds
            np.add.at(accum, (y_out, x_out), rgb_srgb.astype(np.float32))
        processed_hits += int(rec.shape[0])
        done_ops = first_pass_ops + processed_hits
        emit_progress(done_ops, total_ops, "python_compose", task="compose")

    emit_progress(total_ops, total_ops, "python_compose", task="compose", force=True)

    if ds > 1:
        img_f = np.clip(accum / float(ds * ds), 0.0, 1.0)
        if args.dither > 0.0:
            yy, xx = np.indices((out_h, out_w), dtype=np.int64)
            dither = bayer_dither(xx.ravel(), yy.ravel()).reshape(out_h, out_w, 1) * (args.dither / 255.0)
            img_f = np.clip(img_f + dither, 0.0, 1.0)
        img = np.clip(img_f * 255.0 + 0.5, 0.0, 255.0).astype(np.uint8)

    render_conditions = {
        "pipeline": "Blackhole/render_collisions.py",
        "created": datetime.now().isoformat(timespec="seconds"),
        "input": os.path.basename(args.input),
        "renderWidth": int(W),
        "renderHeight": int(H),
        "outputWidth": int(img.shape[1]),
        "outputHeight": int(img.shape[0]),
        "downsample": int(args.downsample),
        "metric": metric,
        "look": str(look),
        "spectralEncoding": spectral_encoding,
        "spectralStepNm": float(args.spectral_step),
        "rcp": float(rcp),
        "innerEdgeMult": float(args.inner_edge_mult),
        "dither": float(args.dither),
        "exposure": float(exposure),
        "autoExposure": bool(args.exposure <= 0.0),
        "exposureSamples": int(args.exposure_samples),
    }
    for key in (
        "preset",
        "spin",
        "h",
        "maxSteps",
        "diskH",
        "fov",
        "roll",
        "camX",
        "camY",
        "camZ",
        "kerrSubsteps",
        "kerrTol",
        "kerrEscapeMult",
        "kerrRadialScale",
        "kerrAzimuthScale",
        "kerrImpactScale",
    ):
        if key in meta:
            render_conditions[key] = meta[key]

    ext = os.path.splitext(args.output)[1].lower()
    exif_payload = build_png_exif_payload(render_conditions) if ext in ("", ".png") else None
    itxt_payload = None
    text_payload = None
    if ext in ("", ".png"):
        full_json = json.dumps(render_conditions, ensure_ascii=False, separators=(",", ":"), sort_keys=True)
        itxt_payload = build_png_itxt_payload("BlackholeRenderConditions", full_json)
        summary = (
            f"metric={metric};look={look};render={W}x{H};out={img.shape[1]}x{img.shape[0]};"
            f"downsample={args.downsample};spectralStepNm={args.spectral_step};"
            f"spin={meta.get('spin', 'n/a')};preset={meta.get('preset', 'n/a')}"
        )
        text_payload = build_png_text_payload("Description", summary)
    save_rgb_image(
        args.output,
        img,
        exif_payload=exif_payload,
        itxt_payload=itxt_payload,
        text_payload=text_payload,
    )
    print(f"Saved {args.output}")


if __name__ == "__main__":
    main()
