#!/usr/bin/env python3
"""Convert float4 linear32 radiance into Bayer CFA camera RAW buffers.

The default output is intentionally simple and explicit: one float32 sample per
pixel in an RGGB mosaic. It preserves the renderer's linear scene values without
demosaic, tone mapping, display gamma, bloom, flare, or color grading. The
optional u16 mode applies a documented reference sensor/ADC calibration; it is
not a proprietary camera RAW container.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

import numpy as np


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--input-linear32", required=True)
    p.add_argument("--input-meta", default="")
    p.add_argument("--output-raw", required=True)
    p.add_argument("--width", type=int, required=True)
    p.add_argument("--height", type=int, required=True)
    p.add_argument("--format", default="bayer-rggb-f32", choices=["bayer-rggb-f32", "bayer-rggb-u16"])
    p.add_argument("--cfa", default="rggb", choices=["rggb"])
    p.add_argument("--black-level", type=float, default=0.0)
    p.add_argument("--white-level", type=float, default=0.0, help="f32: 0 preserves unclipped values; u16: 0 derives p99.9 reference white")
    p.add_argument("--sensor-qe", type=float, default=0.55)
    p.add_argument("--sensor-full-well-electrons", type=float, default=60000.0)
    p.add_argument("--sensor-read-noise-electrons", type=float, default=0.0)
    p.add_argument("--sensor-shot-noise", choices=["off", "on"], default="off")
    p.add_argument("--sensor-seed", type=int, default=1729)
    return p.parse_args()


def load_linear32(path: Path, width: int, height: int) -> np.ndarray:
    data = np.fromfile(path, dtype="<f4")
    expected = width * height * 4
    if data.size != expected:
        raise ValueError(f"{path} contains {data.size} float32 values; expected {expected}")
    linear = data.reshape(height, width, 4)
    if not np.all(np.isfinite(linear)):
        raise ValueError(f"{path} contains non-finite values")
    return linear


def rggb_mosaic(rgb: np.ndarray) -> np.ndarray:
    h, w, _ = rgb.shape
    raw = np.empty((h, w), dtype=np.float32)
    yy, xx = np.indices((h, w))
    red = (yy % 2 == 0) & (xx % 2 == 0)
    blue = (yy % 2 == 1) & (xx % 2 == 1)
    green = ~(red | blue)
    raw[red] = rgb[..., 0][red]
    raw[green] = rgb[..., 1][green]
    raw[blue] = rgb[..., 2][blue]
    return raw


def stats(raw: np.ndarray) -> dict[str, float]:
    return {
        "min": float(np.min(raw)),
        "max": float(np.max(raw)),
        "mean": float(np.mean(raw)),
        "p50": float(np.percentile(raw, 50)),
        "p95": float(np.percentile(raw, 95)),
        "p99": float(np.percentile(raw, 99)),
        "active_fraction": float(np.mean(raw > 1e-7)),
    }


def meta_float(meta: dict[str, Any], key: str, default: float) -> float:
    value = meta.get(key)
    try:
        f = float(value)
    except (TypeError, ValueError):
        return default
    return f if np.isfinite(f) else default


def exposure_scale(source_meta: dict[str, Any]) -> float:
    shutter = max(meta_float(source_meta, "cameraShutterSeconds", 1.0 / 60.0), 1e-9)
    f_number = max(meta_float(source_meta, "cameraFNumber", 8.0), 1e-6)
    return float((shutter / (1.0 / 60.0)) * ((8.0 / f_number) ** 2))


def adc_u16_from_rggb(raw: np.ndarray, args: argparse.Namespace, source_meta: dict[str, Any]) -> tuple[np.ndarray, dict[str, Any]]:
    active = raw[raw > 0.0]
    if args.white_level > 0.0:
        white_radiance = float(args.white_level)
        white_source = "explicit"
    elif active.size:
        white_radiance = float(max(np.percentile(active, 99.9) / 0.92, 1e-20))
        white_source = "p99.9-active/0.92"
    else:
        white_radiance = 1.0
        white_source = "fallback-empty"

    qe = float(np.clip(args.sensor_qe, 0.0, 1.0))
    full_well = max(float(args.sensor_full_well_electrons), 1.0)
    read_noise = max(float(args.sensor_read_noise_electrons), 0.0)
    iso = max(meta_float(source_meta, "cameraISO", 100.0), 1e-6)
    gain = iso / 100.0
    exp_scale = exposure_scale(source_meta)

    normalized = np.clip(raw / np.float32(white_radiance), 0.0, 1.0).astype(np.float32)
    electrons = normalized * np.float32(full_well * exp_scale * (qe / 0.55))
    rng = np.random.default_rng(args.sensor_seed)
    if args.sensor_shot_noise == "on":
        electrons = rng.poisson(np.maximum(electrons, 0.0)).astype(np.float32)
    if read_noise > 0.0:
        electrons = electrons + rng.normal(0.0, read_noise, size=electrons.shape).astype(np.float32)
    electrons = np.clip(electrons, 0.0, full_well)

    black = int(round(args.black_level if args.black_level > 0.0 else 512.0))
    white = 65535
    digital = black + (electrons / np.float32(full_well)) * np.float32(white - black) * np.float32(gain)
    adc = np.clip(np.rint(digital), 0, 65535).astype("<u2", copy=False)
    sensor_meta = {
        "calibrationWhiteRadiance": white_radiance,
        "calibrationWhiteSource": white_source,
        "referenceFNumber": 8.0,
        "referenceShutterSeconds": 1.0 / 60.0,
        "exposureScale": exp_scale,
        "sensorQuantumEfficiency": qe,
        "sensorFullWellElectrons": full_well,
        "sensorReadNoiseElectrons": read_noise,
        "sensorShotNoise": args.sensor_shot_noise,
        "sensorSeed": args.sensor_seed,
        "sensorISO": iso,
        "sensorISOGain": gain,
        "blackLevelADU": black,
        "whiteLevelADU": white,
        "adcBits": 16,
    }
    return adc, sensor_meta


def main() -> None:
    args = parse_args()
    input_path = Path(args.input_linear32)
    output_path = Path(args.output_raw)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    linear = load_linear32(input_path, args.width, args.height)
    rgb = np.maximum(linear[..., :3], 0.0).astype(np.float32, copy=False)
    raw = rggb_mosaic(rgb)

    source_meta: dict[str, Any] = {}
    if args.input_meta:
        meta_path = Path(args.input_meta)
        if meta_path.exists():
            source_meta = json.loads(meta_path.read_text(encoding="utf-8"))

    sensor_meta: dict[str, Any] = {}
    if args.format == "bayer-rggb-f32":
        if args.white_level > 0.0:
            raw = np.minimum(raw, np.float32(args.white_level))
        raw = np.maximum(raw, np.float32(args.black_level))
        raw.astype("<f4", copy=False).tofile(output_path)
        dtype = "float32-le"
        version = "camera_raw_bayer_f32_v1"
        kind = "ideal-linear-sensor-raw"
        white_level: float | None = None if args.white_level <= 0.0 else args.white_level
        black_level: float | int = args.black_level
        sample_stats = stats(raw)
    else:
        adc, sensor_meta = adc_u16_from_rggb(raw, args, source_meta)
        adc.tofile(output_path)
        dtype = "uint16-le"
        version = "camera_raw_bayer_u16_v1"
        kind = "reference-sensor-adc-raw"
        white_level = sensor_meta["whiteLevelADU"]
        black_level = sensor_meta["blackLevelADU"]
        sample_stats = stats(adc.astype(np.float32))

    meta = {
        "version": version,
        "kind": kind,
        "format": args.format,
        "cfaPattern": "RGGB",
        "width": args.width,
        "height": args.height,
        "dtype": dtype,
        "samplesPerPixel": 1,
        "byteCount": int(output_path.stat().st_size),
        "blackLevel": black_level,
        "whiteLevel": white_level,
        "demosaiced": False,
        "toneMapped": False,
        "displayGammaApplied": False,
        "sourceLinear32": str(input_path),
        "sourceMetadata": args.input_meta,
        "sourcePresentationMode": source_meta.get("presentationMode"),
        "sourceCameraModel": source_meta.get("cameraModel"),
        "sourceCameraProfile": source_meta.get("cameraProfile"),
        "sourceLook": source_meta.get("look"),
        "sourceExposureMode": source_meta.get("exposureMode"),
        "sourceCameraFNumber": source_meta.get("cameraFNumber"),
        "sourceCameraISO": source_meta.get("cameraISO"),
        "sourceCameraShutterSeconds": source_meta.get("cameraShutterSeconds"),
        "sourceWidth": source_meta.get("width"),
        "sourceHeight": source_meta.get("height"),
        "channelAtPixel": {
            "evenRowEvenCol": "R",
            "evenRowOddCol": "G",
            "oddRowEvenCol": "G",
            "oddRowOddCol": "B",
        },
        "sensorModel": sensor_meta,
        "stats": sample_stats,
        "contract": [
            "one CFA sample per pixel",
            "no demosaic",
            "no tone mapping",
            "no display gamma",
            "no cinematic layer",
        ],
    }
    Path(str(output_path) + ".json").write_text(json.dumps(meta, indent=2, sort_keys=True), encoding="utf-8")
    print(f"camera_raw={output_path}")
    print(f"camera_raw_meta={output_path}.json")


if __name__ == "__main__":
    main()
