#!/usr/bin/env python3
"""Phase 5 camera-raw linear32 sidecar and ideal CFA RAW validation.

This validates the current camera-raw contract: a camera-raw audit render can
emit both the float4 linear32 radiance/depth sidecar and a dedicated ideal Bayer
CFA float32 sensor RAW buffer, with presentation effects disabled. The CFA file
is intentionally pre-demosaic and does not claim to emulate a proprietary camera
RAW container.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import subprocess
from pathlib import Path
from typing import Any

import numpy as np


ROOT = Path(__file__).resolve().parents[1]
RUN_PIPELINE = ROOT / "Blackhole" / "run_pipeline.sh"


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--out-dir", default="/private/tmp/bh_camera_raw_sidecar")
    p.add_argument("--width", type=int, default=64)
    p.add_argument("--height", type=int, default=36)
    p.add_argument("--quality", default="preview", choices=["preview", "hq"])
    p.add_argument("--source-model", default="canonical-visible-disk-v1")
    p.add_argument("--no-build", action="store_true")
    return p.parse_args()


def run(cmd: list[str], env: dict[str, str]) -> subprocess.CompletedProcess[str]:
    print("+", " ".join(cmd), flush=True)
    return subprocess.run(cmd, cwd=str(ROOT), env=env, text=True, capture_output=True)


def finite_stats(path: Path, width: int, height: int) -> dict[str, Any]:
    data = np.fromfile(path, dtype=np.float32)
    expected_values = width * height * 4
    stats: dict[str, Any] = {
        "value_count": int(data.size),
        "expected_value_count": expected_values,
        "byte_count": int(path.stat().st_size),
        "expected_byte_count": expected_values * 4,
        "size_matches": int(data.size) == expected_values,
    }
    if data.size != expected_values:
        return stats
    rgba = data.reshape((height, width, 4))
    rgb = rgba[..., :3]
    depth = rgba[..., 3]
    finite = np.isfinite(rgba)
    active_rgb = np.maximum(rgb, 0.0)
    luminance = active_rgb[..., 0] * 0.2126 + active_rgb[..., 1] * 0.7152 + active_rgb[..., 2] * 0.0722
    stats.update(
        {
            "finite_fraction": float(np.mean(finite)),
            "rgb_min": float(np.min(rgb)),
            "rgb_max": float(np.max(rgb)),
            "luma_mean": float(np.mean(luminance)),
            "luma_p99": float(np.percentile(luminance, 99.0)),
            "active_luma_fraction": float(np.mean(luminance > 1e-7)),
            "depth_finite_fraction": float(np.mean(np.isfinite(depth))),
            "depth_min": float(np.min(depth[np.isfinite(depth)])) if np.any(np.isfinite(depth)) else None,
            "depth_max": float(np.max(depth[np.isfinite(depth)])) if np.any(np.isfinite(depth)) else None,
        }
    )
    return stats


def cfa_stats(path: Path, width: int, height: int) -> dict[str, Any]:
    data = np.fromfile(path, dtype=np.float32)
    expected_values = width * height
    stats: dict[str, Any] = {
        "value_count": int(data.size),
        "expected_value_count": expected_values,
        "byte_count": int(path.stat().st_size),
        "expected_byte_count": expected_values * 4,
        "size_matches": int(data.size) == expected_values,
    }
    if data.size != expected_values:
        return stats
    raw = data.reshape((height, width))
    finite = np.isfinite(raw)
    stats.update(
        {
            "finite_fraction": float(np.mean(finite)),
            "raw_min": float(np.min(raw)),
            "raw_max": float(np.max(raw)),
            "raw_mean": float(np.mean(raw)),
            "raw_p99": float(np.percentile(raw, 99.0)),
            "active_fraction": float(np.mean(raw > 1e-7)),
            "red_site_fraction": float(np.mean(raw[0::2, 0::2] > 1e-7)),
            "green_site_fraction": float(
                np.mean(np.concatenate([raw[0::2, 1::2].ravel(), raw[1::2, 0::2].ravel()]) > 1e-7)
            ),
            "blue_site_fraction": float(np.mean(raw[1::2, 1::2] > 1e-7)),
        }
    )
    return stats


def cfa_u16_stats(path: Path, width: int, height: int) -> dict[str, Any]:
    data = np.fromfile(path, dtype=np.uint16)
    expected_values = width * height
    stats: dict[str, Any] = {
        "value_count": int(data.size),
        "expected_value_count": expected_values,
        "byte_count": int(path.stat().st_size),
        "expected_byte_count": expected_values * 2,
        "size_matches": int(data.size) == expected_values,
    }
    if data.size != expected_values:
        return stats
    raw = data.reshape((height, width))
    stats.update(
        {
            "raw_min": int(np.min(raw)),
            "raw_max": int(np.max(raw)),
            "raw_mean": float(np.mean(raw)),
            "raw_p99": float(np.percentile(raw, 99.0)),
            "above_black_fraction": float(np.mean(raw > 512)),
            "saturated_fraction": float(np.mean(raw >= 65535)),
        }
    )
    return stats


def expected_rggb_from_linear32(path: Path, width: int, height: int) -> np.ndarray:
    rgba = np.fromfile(path, dtype=np.float32).reshape((height, width, 4))
    rgb = np.maximum(rgba[..., :3], 0.0)
    expected = np.empty((height, width), dtype=np.float32)
    expected[0::2, 0::2] = rgb[0::2, 0::2, 0]
    expected[0::2, 1::2] = rgb[0::2, 1::2, 1]
    expected[1::2, 0::2] = rgb[1::2, 0::2, 1]
    expected[1::2, 1::2] = rgb[1::2, 1::2, 2]
    return expected


def cfa_matches_linear32(raw_path: Path, linear32_path: Path, width: int, height: int) -> dict[str, Any]:
    raw = np.fromfile(raw_path, dtype=np.float32).reshape((height, width))
    expected = expected_rggb_from_linear32(linear32_path, width, height)
    diff = raw - expected
    return {
        "max_abs_error": float(np.max(np.abs(diff))),
        "rmse": float(np.sqrt(np.mean(diff * diff))),
        "allclose": bool(np.allclose(raw, expected, rtol=0.0, atol=1e-7)),
    }


def main() -> None:
    args = parse_args()
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    image = out_dir / "camera_raw.png"
    raw = out_dir / "camera_raw.linear32f32"
    sensor_raw = out_dir / "camera_raw_bayer_rggb_f32.raw"
    sensor_adc_raw = out_dir / "camera_raw_bayer_rggb_u16.raw"
    meta = Path(str(raw) + ".json")
    sensor_meta = Path(str(sensor_raw) + ".json")
    sensor_adc_meta = Path(str(sensor_adc_raw) + ".json")
    env = os.environ.copy()
    env.setdefault("BH_DERIVED_DATA_PATH", str(out_dir / "DerivedData"))
    env.setdefault("BH_ETA_HISTORY", str(out_dir / "eta_history.json"))

    cmd = [
        "bash",
        str(RUN_PIPELINE),
        "--source-model",
        args.source_model,
        "--quality",
        args.quality,
        "--presentation",
        "camera-raw",
        "--camera-model",
        "legacy",
        "--camera-profile",
        "ideal",
        "--look",
        "linear",
        "--exposure-mode",
        "fixed",
        "--exposure-ev",
        "0",
        "--camera-psf-sigma",
        "0",
        "--camera-read-noise",
        "0",
        "--camera-shot-noise",
        "0",
        "--camera-flare",
        "0",
        "--camera-dof-strength",
        "0",
        "--background",
        "off",
        "--hdr-intermediate",
        "--hdr-out",
        str(raw),
        "--camera-raw-out",
        str(sensor_raw),
        "--width",
        str(args.width),
        "--height",
        str(args.height),
        "--output",
        str(image),
    ]
    if args.no_build:
        cmd.append("--no-build")

    completed = run(cmd, env)
    adc_cmd = [
        os.environ.get("BH_PYTHON", "python3"),
        str(ROOT / "Blackhole" / "scripts" / "linear32_to_camera_raw.py"),
        "--input-linear32",
        str(raw),
        "--input-meta",
        str(meta),
        "--output-raw",
        str(sensor_adc_raw),
        "--width",
        str(args.width),
        "--height",
        str(args.height),
        "--format",
        "bayer-rggb-u16",
        "--cfa",
        "rggb",
        "--black-level",
        "512",
        "--sensor-shot-noise",
        "on",
        "--sensor-read-noise-electrons",
        "1.5",
        "--sensor-seed",
        "20260616",
    ]
    adc_completed = subprocess.run(adc_cmd, cwd=str(ROOT), env=env, text=True, capture_output=True) if completed.returncode == 0 else None
    raw_exists = raw.exists()
    sensor_raw_exists = sensor_raw.exists()
    sensor_adc_exists = sensor_adc_raw.exists()
    image_exists = image.exists()
    meta_exists = meta.exists()
    sensor_meta_exists = sensor_meta.exists()
    sensor_adc_meta_exists = sensor_adc_meta.exists()
    raw_stats = finite_stats(raw, args.width, args.height) if raw_exists else {}
    sensor_raw_stats = cfa_stats(sensor_raw, args.width, args.height) if sensor_raw_exists else {}
    sensor_adc_stats = cfa_u16_stats(sensor_adc_raw, args.width, args.height) if sensor_adc_exists else {}
    cfa_match = cfa_matches_linear32(sensor_raw, raw, args.width, args.height) if sensor_raw_exists and raw_exists else {}
    meta_json: dict[str, Any] = {}
    if meta_exists:
        meta_json = json.loads(meta.read_text(encoding="utf-8"))
    sensor_meta_json: dict[str, Any] = {}
    if sensor_meta_exists:
        sensor_meta_json = json.loads(sensor_meta.read_text(encoding="utf-8"))
    sensor_adc_meta_json: dict[str, Any] = {}
    if sensor_adc_meta_exists:
        sensor_adc_meta_json = json.loads(sensor_adc_meta.read_text(encoding="utf-8"))

    gates = {
        "command_succeeded": completed.returncode == 0,
        "image_written": image_exists,
        "linear32_sidecar_written": raw_exists,
        "linear32_metadata_written": meta_exists,
        "linear32_size_matches": bool(raw_stats.get("size_matches", False)),
        "linear32_finite": math.isclose(float(raw_stats.get("finite_fraction", 0.0)), 1.0),
        "linear32_has_active_radiance": float(raw_stats.get("active_luma_fraction", 0.0)) > 0.005,
        "sensor_raw_written": sensor_raw_exists,
        "sensor_raw_metadata_written": sensor_meta_exists,
        "sensor_raw_size_matches": bool(sensor_raw_stats.get("size_matches", False)),
        "sensor_raw_finite": math.isclose(float(sensor_raw_stats.get("finite_fraction", 0.0)), 1.0),
        "sensor_raw_has_active_samples": float(sensor_raw_stats.get("active_fraction", 0.0)) > 0.005,
        "sensor_raw_matches_linear32_rggb": bool(cfa_match.get("allclose", False)),
        "sensor_raw_is_bayer_rggb_f32": sensor_meta_json.get("format") == "bayer-rggb-f32"
        and sensor_meta_json.get("cfaPattern") == "RGGB"
        and sensor_meta_json.get("demosaiced") is False,
        "metadata_marks_camera_raw": meta_json.get("presentationMode") == "camera-raw",
        "metadata_marks_identity_camera": meta_json.get("cameraModel") == "legacy"
        and meta_json.get("cameraProfile") == "ideal",
        "sensor_metadata_sources_camera_raw": sensor_meta_json.get("sourcePresentationMode") == "camera-raw",
        "sensor_adc_command_succeeded": adc_completed is not None and adc_completed.returncode == 0,
        "sensor_adc_raw_written": sensor_adc_exists,
        "sensor_adc_metadata_written": sensor_adc_meta_exists,
        "sensor_adc_size_matches": bool(sensor_adc_stats.get("size_matches", False)),
        "sensor_adc_above_black": float(sensor_adc_stats.get("above_black_fraction", 0.0)) > 0.005,
        "sensor_adc_not_fully_saturated": float(sensor_adc_stats.get("saturated_fraction", 1.0)) < 0.25,
        "sensor_adc_is_bayer_rggb_u16": sensor_adc_meta_json.get("format") == "bayer-rggb-u16"
        and sensor_adc_meta_json.get("dtype") == "uint16-le"
        and sensor_adc_meta_json.get("sensorModel", {}).get("adcBits") == 16
        and sensor_adc_meta_json.get("sensorModel", {}).get("sensorShotNoise") == "on",
        "run_pipeline_accepts_u16_format": "bayer-rggb-u16" in (ROOT / "Blackhole" / "run_pipeline.sh").read_text(encoding="utf-8"),
    }
    report = {
        "phase": "Phase 5 camera-raw linear32 sidecar",
        "passed": all(gates.values()),
        "command": cmd,
        "returncode": completed.returncode,
        "stdout_tail": completed.stdout.strip().splitlines()[-30:],
        "stderr_tail": completed.stderr.strip().splitlines()[-30:],
        "outputs": {
            "image": str(image),
            "linear32_sidecar": str(raw),
            "metadata": str(meta),
            "sensor_raw": str(sensor_raw),
            "sensor_raw_metadata": str(sensor_meta),
            "sensor_adc_raw": str(sensor_adc_raw),
            "sensor_adc_metadata": str(sensor_adc_meta),
        },
        "gates": gates,
        "linear32_stats": raw_stats,
        "sensor_raw_stats": sensor_raw_stats,
        "sensor_adc_stats": sensor_adc_stats,
        "sensor_raw_match": cfa_match,
        "metadata_subset": {
            "presentationMode": meta_json.get("presentationMode"),
            "cameraModel": meta_json.get("cameraModel"),
            "cameraProfile": meta_json.get("cameraProfile"),
            "look": meta_json.get("look"),
            "exposureMode": meta_json.get("exposureMode"),
            "backgroundMode": meta_json.get("backgroundMode"),
        },
        "sensor_raw_metadata_subset": {
            "version": sensor_meta_json.get("version"),
            "kind": sensor_meta_json.get("kind"),
            "format": sensor_meta_json.get("format"),
            "cfaPattern": sensor_meta_json.get("cfaPattern"),
            "demosaiced": sensor_meta_json.get("demosaiced"),
            "toneMapped": sensor_meta_json.get("toneMapped"),
            "displayGammaApplied": sensor_meta_json.get("displayGammaApplied"),
            "sourcePresentationMode": sensor_meta_json.get("sourcePresentationMode"),
            "sourceExposureMode": sensor_meta_json.get("sourceExposureMode"),
            "sourceCameraISO": sensor_meta_json.get("sourceCameraISO"),
        },
        "sensor_adc_metadata_subset": {
            "version": sensor_adc_meta_json.get("version"),
            "kind": sensor_adc_meta_json.get("kind"),
            "format": sensor_adc_meta_json.get("format"),
            "dtype": sensor_adc_meta_json.get("dtype"),
            "sensorModel": sensor_adc_meta_json.get("sensorModel"),
        },
        "contract_gaps": [
            "This validates an ideal linear Bayer CFA float32 RAW buffer, not a proprietary camera RAW container.",
            "The u16 path is a documented reference sensor/ADC calibration, not a proprietary camera RAW container.",
            "Future work can add optional demosaic/rendered-camera comparison.",
        ],
    }
    report_path = out_dir / "camera_raw_sidecar_metrics.json"
    report_path.write_text(json.dumps(report, indent=2, sort_keys=True), encoding="utf-8")
    print(json.dumps(report, indent=2, sort_keys=True))
    print(f"report={report_path}")
    if not report["passed"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
