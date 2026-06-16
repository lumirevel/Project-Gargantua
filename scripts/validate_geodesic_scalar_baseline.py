#!/usr/bin/env python3
"""Phase 2 geodesic scalar baseline harness.

This script does not tune geodesics and does not render beauty images. It wraps
the existing single-ray comparison tool, extracts scalar invariants, and writes
a repeatable JSON report under /private/tmp by default.

Default behavior exits successfully when the harness runs, the Kerr
null/Lz/Q/finite-radius checks remain bounded, the Kerr a=0 metric matches the
Schwarzschild BL metric, a calibrated Schwarzschild-vs-Kerr(a=0) Hamiltonian
trajectory fixture agrees within tolerance, and the Schwarzschild photon-sphere
fixture remains bounded. A calibrated image-plane near-critical grid is also
hard-gated with a small step size.
"""

from __future__ import annotations

import argparse
import csv
import importlib.util
import json
import math
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
TRACE = ROOT / "Blackhole" / "scripts" / "trace_ray_compare.py"


@dataclass(frozen=True)
class Case:
    name: str
    pixel_x: int
    pixel_y: int
    spin: float
    h: float
    max_steps: int
    stress: bool = False


BASE_CASES = [
    Case("off_axis_schwarzschild_limit_probe", 120, 90, 0.0, 0.002, 500),
    Case("off_axis_high_spin_probe", 120, 90, 0.92, 0.002, 500),
]

CRITICAL_GRID_OFFSETS = [
    (-4, -2),
    (0, -2),
    (4, -2),
    (-4, 0),
    (0, 0),
    (4, 0),
    (-4, 2),
    (0, 2),
    (4, 2),
]


def critical_grid_cases() -> list[Case]:
    center_x = 160
    center_y = 90
    cases: list[Case] = []
    for dx, dy in CRITICAL_GRID_OFFSETS:
        x_tag = f"m{abs(dx)}" if dx < 0 else f"p{dx}"
        y_tag = f"m{abs(dy)}" if dy < 0 else f"p{dy}"
        cases.append(
            Case(
                f"critical_grid_dx{x_tag}_dy{y_tag}_h002",
                center_x + dx,
                center_y + dy,
                0.0,
                0.002,
                500,
                stress=True,
            )
        )
    return cases


CASES = BASE_CASES + critical_grid_cases()


def load_trace_module() -> Any:
    spec = importlib.util.spec_from_file_location("trace_ray_compare", TRACE)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"failed to load {TRACE}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--out-dir", default="/private/tmp/bh_geodesic_scalar_baseline")
    p.add_argument("--width", type=int, default=320)
    p.add_argument("--height", type=int, default=180)
    p.add_argument("--preset", default="interstellar")
    p.add_argument("--fail-on-contract-gaps", action="store_true")
    return p.parse_args()


def run_case(args: argparse.Namespace, case: Case, out_dir: Path) -> dict[str, Any]:
    stem = out_dir / case.name
    csv_path = stem.with_suffix(".csv")
    full_state = out_dir / f"{case.name}_full_state.csv"
    analysis_json = out_dir / f"{case.name}_analysis.json"
    cmd = [
        sys.executable,
        str(TRACE),
        "--preset",
        args.preset,
        "--width",
        str(args.width),
        "--height",
        str(args.height),
        "--pixel-x",
        str(case.pixel_x),
        "--pixel-y",
        str(case.pixel_y),
        "--spin",
        str(case.spin),
        "--h",
        str(case.h),
        "--max-steps",
        str(case.max_steps),
        "--kerr-tol",
        "1e-6",
        "--csv",
        str(csv_path),
        "--full-state-csv",
        str(full_state),
        "--analysis-json",
        str(analysis_json),
    ]
    completed = subprocess.run(cmd, cwd=str(ROOT), text=True, capture_output=True)
    row: dict[str, Any] = {
        "name": case.name,
        "stress": case.stress,
        "pixel": {"x": case.pixel_x, "y": case.pixel_y},
        "spin": case.spin,
        "h": case.h,
        "max_steps": case.max_steps,
        "command": cmd,
        "returncode": completed.returncode,
        "stdout_tail": completed.stdout.strip().splitlines()[-8:],
        "stderr_tail": completed.stderr.strip().splitlines()[-8:],
        "outputs": {
            "csv": str(csv_path),
            "full_state_csv": str(full_state),
            "analysis_json": str(analysis_json),
        },
    }
    if completed.returncode != 0:
        row["harness_passed"] = False
        row["gate_failures"] = ["trace_ray_compare failed"]
        return row

    analysis = json.loads(analysis_json.read_text(encoding="utf-8"))
    state_metrics = summarize_full_state(full_state, case)
    row["trace_analysis"] = analysis
    row["scalar_metrics"] = state_metrics
    row["gate_failures"] = gate_failures(state_metrics, case)
    row["harness_passed"] = not row["gate_failures"]
    return row


def finite_float(value: str) -> float | None:
    try:
        f = float(value)
    except (TypeError, ValueError):
        return None
    if not math.isfinite(f):
        return None
    return f


def rel_drift(values: list[float]) -> float | None:
    if len(values) < 2:
        return None
    span = max(values) - min(values)
    scale = max(abs(values[0]), 1e-12)
    return span / scale


def percentile(values: list[float], q: float) -> float | None:
    if not values:
        return None
    ordered = sorted(values)
    idx = min(len(ordered) - 1, max(0, int(round((len(ordered) - 1) * q))))
    return ordered[idx]


def schwarzschild_cov_metric(r: float, theta: float) -> dict[str, float]:
    sth = math.sin(theta)
    w = 1.0 - 2.0 / r
    return {
        "gtt": -w,
        "gtphi": 0.0,
        "gphiphi": r * r * sth * sth,
        "grr": 1.0 / w,
        "gthth": r * r,
    }


def schwarzschild_inv_metric(r: float, theta: float) -> dict[str, float]:
    sth = max(math.sin(theta), 1e-10)
    w = 1.0 - 2.0 / r
    return {
        "gtt": -1.0 / w,
        "gtphi": 0.0,
        "gphiphi": 1.0 / (r * r * sth * sth),
        "grr": w,
        "gthth": 1.0 / (r * r),
    }


def metric_rel_error(actual: float, expected: float) -> float:
    return abs(actual - expected) / max(abs(expected), 1e-14)


def schwarzschild_limit_metric_check() -> dict[str, Any]:
    trace = load_trace_module()
    radii = [2.25, 3.0, 6.0, 10.0, 30.0]
    thetas = [0.30, 0.90, 0.5 * math.pi, 2.20, 2.84]
    cov_errors: list[float] = []
    inv_errors: list[float] = []
    worst: dict[str, Any] = {
        "kind": "",
        "component": "",
        "r": None,
        "theta": None,
        "actual": None,
        "expected": None,
        "relative_error": -1.0,
    }

    for r in radii:
        for theta in thetas:
            expected_cov = schwarzschild_cov_metric(r, theta)
            actual_cov = trace.kerr_cov_metric(r, theta, 0.0)
            expected_inv = schwarzschild_inv_metric(r, theta)
            actual_inv = trace.kerr_inv_metric(r, theta, 0.0)
            for component in ("gtt", "gtphi", "gphiphi", "grr", "gthth"):
                err = metric_rel_error(actual_cov[component], expected_cov[component])
                cov_errors.append(err)
                if err > worst["relative_error"]:
                    worst = {
                        "kind": "covariant",
                        "component": component,
                        "r": r,
                        "theta": theta,
                        "actual": actual_cov[component],
                        "expected": expected_cov[component],
                        "relative_error": err,
                    }
                err = metric_rel_error(actual_inv[component], expected_inv[component])
                inv_errors.append(err)
                if err > worst["relative_error"]:
                    worst = {
                        "kind": "inverse",
                        "component": component,
                        "r": r,
                        "theta": theta,
                        "actual": actual_inv[component],
                        "expected": expected_inv[component],
                        "relative_error": err,
                    }

    max_cov = max(cov_errors)
    max_inv = max(inv_errors)
    threshold = 1e-12
    return {
        "description": "Kerr metric at a=0 equals Schwarzschild BL metric over a small r/theta grid.",
        "radii": radii,
        "thetas": thetas,
        "max_covariant_relative_error": max_cov,
        "max_inverse_relative_error": max_inv,
        "threshold": threshold,
        "worst_component": worst,
        "passed": max(max_cov, max_inv) < threshold,
    }


def schwarzschild_hamiltonian_rhs(state: dict[str, float], lz: float) -> tuple[dict[str, float], float]:
    r = max(state["r"], 1e-6)
    theta = min(max(state["theta"], 1e-5), math.pi - 1e-5)
    f = 1.0 - 2.0 / r
    s = max(math.sin(theta), 1e-10)
    c = math.cos(theta)
    p_t = -1.0
    p_r = state["pr"]
    p_theta = state["ptheta"]

    deriv = {
        "t": 1.0 / f,
        "r": f * p_r,
        "theta": p_theta / (r * r),
        "phi": lz / (r * r * s * s),
    }

    dgtt_dr = 2.0 / (r * r * f * f)
    dgrr_dr = 2.0 / (r * r)
    dgthth_dr = -2.0 / (r * r * r)
    dgphiphi_dr = -2.0 / (r * r * r * s * s)
    dgphiphi_dtheta = -2.0 * c / (r * r * s * s * s)

    radial_term = (
        dgtt_dr * p_t * p_t
        + dgphiphi_dr * lz * lz
        + dgrr_dr * p_r * p_r
        + dgthth_dr * p_theta * p_theta
    )
    theta_term = dgphiphi_dtheta * lz * lz
    deriv["pr"] = -0.5 * radial_term
    deriv["ptheta"] = -0.5 * theta_term

    inv = schwarzschild_inv_metric(r, theta)
    null = (
        inv["gtt"] * p_t * p_t
        + inv["grr"] * p_r * p_r
        + inv["gthth"] * p_theta * p_theta
        + inv["gphiphi"] * lz * lz
    )
    return deriv, null


def add_state(state: dict[str, float], deriv: dict[str, float], scale: float) -> dict[str, float]:
    return {key: state[key] + scale * deriv[key] for key in state}


def rk4_step(
    state: dict[str, float],
    h: float,
    lz: float,
    rhs: Any,
) -> dict[str, float]:
    k1, _ = rhs(state, lz)
    k2, _ = rhs(add_state(state, k1, 0.5 * h), lz)
    k3, _ = rhs(add_state(state, k2, 0.5 * h), lz)
    k4, _ = rhs(add_state(state, k3, h), lz)
    return {
        key: state[key] + h * (k1[key] + 2.0 * k2[key] + 2.0 * k3[key] + k4[key]) / 6.0
        for key in state
    }


def trajectory_state_error(a: dict[str, float], b: dict[str, float]) -> float:
    return max(abs(a[key] - b[key]) / max(1.0, abs(a[key])) for key in a)


def schwarzschild_kerr_a0_trajectory_check() -> dict[str, Any]:
    trace = load_trace_module()
    lz = 2.0
    r = 9.0
    theta = 1.2
    p_theta = 0.12
    inv = schwarzschild_inv_metric(r, theta)
    rest = inv["gtt"] + inv["gthth"] * p_theta * p_theta + inv["gphiphi"] * lz * lz
    p_r = -math.sqrt(max(-rest / inv["grr"], 0.0))
    initial_state = {
        "t": 0.0,
        "r": r,
        "theta": theta,
        "phi": 0.1,
        "pr": p_r,
        "ptheta": p_theta,
    }

    def kerr_a0_rhs(state: dict[str, float], lz_value: float) -> tuple[dict[str, float], float]:
        return trace.kerr_rhs_hamiltonian(state, 0.0, lz_value)

    sch_state = dict(initial_state)
    kerr_state = dict(initial_state)
    h = 0.002
    steps = 500
    max_state_error = 0.0
    max_null_abs = 0.0
    for _ in range(steps):
        sch_state = rk4_step(sch_state, h, lz, schwarzschild_hamiltonian_rhs)
        kerr_state = rk4_step(kerr_state, h, lz, kerr_a0_rhs)
        max_state_error = max(max_state_error, trajectory_state_error(sch_state, kerr_state))
        max_null_abs = max(
            max_null_abs,
            abs(schwarzschild_hamiltonian_rhs(sch_state, lz)[1]),
            abs(kerr_a0_rhs(kerr_state, lz)[1]),
        )

    state_threshold = 1e-8
    null_threshold = 1e-7
    return {
        "description": "Independent Schwarzschild Hamiltonian trajectory matches Kerr a=0 Hamiltonian trajectory from the same BL canonical state.",
        "initial_state": initial_state,
        "lz": lz,
        "step_size": h,
        "steps": steps,
        "max_state_relative_error": max_state_error,
        "max_null_abs": max_null_abs,
        "state_threshold": state_threshold,
        "null_threshold": null_threshold,
        "schwarzschild_final_state": sch_state,
        "kerr_a0_final_state": kerr_state,
        "passed": max_state_error < state_threshold and max_null_abs < null_threshold,
    }


def schwarzschild_photon_sphere_check() -> dict[str, Any]:
    trace = load_trace_module()
    lz = 3.0 * math.sqrt(3.0)
    initial_state = {
        "t": 0.0,
        "r": 3.0,
        "theta": 0.5 * math.pi,
        "phi": 0.0,
        "pr": 0.0,
        "ptheta": 0.0,
    }

    def kerr_a0_rhs(state: dict[str, float], lz_value: float) -> tuple[dict[str, float], float]:
        return trace.kerr_rhs_hamiltonian(state, 0.0, lz_value)

    state = dict(initial_state)
    h = 0.001
    steps = 2000
    max_r_drift = 0.0
    max_theta_drift = 0.0
    max_pr_abs = 0.0
    max_null_abs = 0.0
    for _ in range(steps):
        state = rk4_step(state, h, lz, kerr_a0_rhs)
        _, null = kerr_a0_rhs(state, lz)
        max_r_drift = max(max_r_drift, abs(state["r"] - initial_state["r"]))
        max_theta_drift = max(max_theta_drift, abs(state["theta"] - initial_state["theta"]))
        max_pr_abs = max(max_pr_abs, abs(state["pr"]))
        max_null_abs = max(max_null_abs, abs(null))

    r_threshold = 1e-6
    theta_threshold = 1e-10
    pr_threshold = 1e-5
    null_threshold = 1e-10
    return {
        "description": "Kerr a=0 preserves the Schwarzschild equatorial circular photon orbit at r=3M with L/E=3*sqrt(3).",
        "initial_state": initial_state,
        "lz": lz,
        "step_size": h,
        "steps": steps,
        "max_r_drift": max_r_drift,
        "max_theta_drift": max_theta_drift,
        "max_pr_abs": max_pr_abs,
        "max_null_abs": max_null_abs,
        "r_threshold": r_threshold,
        "theta_threshold": theta_threshold,
        "pr_threshold": pr_threshold,
        "null_threshold": null_threshold,
        "final_state": state,
        "passed": (
            max_r_drift < r_threshold
            and max_theta_drift < theta_threshold
            and max_pr_abs < pr_threshold
            and max_null_abs < null_threshold
        ),
    }

def summarize_full_state(path: Path, case: Case) -> dict[str, Any]:
    kerr_rows = 0
    finite_rows = 0
    null_abs: list[float] = []
    lz: list[float] = []
    q_vals: list[float] = []
    r_vals: list[float] = []

    with path.open(newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            if row.get("model") != "kerr":
                continue
            kerr_rows += 1
            vals = {
                "null": finite_float(row.get("null_residual", "")),
                "Lz": finite_float(row.get("Lz", "")),
                "Q": finite_float(row.get("Q", "")),
                "r": finite_float(row.get("r", "")),
            }
            if all(v is not None for v in vals.values()):
                finite_rows += 1
            if vals["null"] is not None:
                null_abs.append(abs(vals["null"]))
            if vals["Lz"] is not None:
                lz.append(vals["Lz"])
            if vals["Q"] is not None:
                q_vals.append(vals["Q"])
            if vals["r"] is not None:
                r_vals.append(vals["r"])

    finite_fraction = finite_rows / max(kerr_rows, 1)
    return {
        "kerr_rows": kerr_rows,
        "finite_fraction": finite_fraction,
        "null_abs_max": max(null_abs) if null_abs else None,
        "null_abs_p99": percentile(null_abs, 0.99),
        "null_abs_mean": sum(null_abs) / len(null_abs) if null_abs else None,
        "lz_relative_drift": rel_drift(lz),
        "q_relative_drift": rel_drift(q_vals),
        "r_min": min(r_vals) if r_vals else None,
        "r_max": max(r_vals) if r_vals else None,
        "r_positive": bool(r_vals and min(r_vals) > 0.0),
        "contract_notes": [
            "Lz is a hard scalar baseline for this harness.",
            "Carter Q is a hard scalar baseline for non-stress Kerr probes.",
            "Kerr a=0 metric identity is a hard gate; Schwarzschild-vs-Kerr(a=0) trajectory agreement still needs a calibrated comparison path.",
        ],
    }


def gate_failures(metrics: dict[str, Any], case: Case) -> list[str]:
    failures: list[str] = []
    if case.stress:
        if metrics["kerr_rows"] < max(900, case.max_steps):
            failures.append("too few Kerr states for near-critical stress gate")
        if metrics["finite_fraction"] < 0.999:
            failures.append("non-finite Kerr state fraction exceeds 0.1% in near-critical stress gate")
        if not metrics["r_positive"]:
            failures.append("Kerr radius became non-positive in near-critical stress gate")
        if metrics["null_abs_p99"] is None or metrics["null_abs_p99"] > 1e-6:
            failures.append("Kerr null residual p99 exceeds 1e-6 in near-critical stress gate")
        if metrics["lz_relative_drift"] is None or metrics["lz_relative_drift"] > 1e-9:
            failures.append("Kerr Lz drift exceeds 1e-9 in near-critical stress gate")
        if metrics["q_relative_drift"] is None or metrics["q_relative_drift"] > 1e-8:
            failures.append("Kerr Carter Q drift exceeds 1e-8 in near-critical stress gate")
        return failures

    if metrics["kerr_rows"] < max(100, case.max_steps // 2):
        failures.append("too few Kerr states for scalar baseline")
    if metrics["finite_fraction"] < 0.99:
        failures.append("non-finite Kerr state fraction exceeds 1%")
    if not metrics["r_positive"]:
        failures.append("Kerr radius became non-positive")
    if metrics["null_abs_p99"] is None or metrics["null_abs_p99"] > 1e-5:
        failures.append("Kerr null residual p99 exceeds 1e-5")
    if metrics["lz_relative_drift"] is None or metrics["lz_relative_drift"] > 1e-9:
        failures.append("Kerr Lz drift exceeds 1e-9")
    if metrics["q_relative_drift"] is None or metrics["q_relative_drift"] > 1e-8:
        failures.append("Kerr Carter Q drift exceeds 1e-8")
    return failures


def main() -> None:
    args = parse_args()
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    cases = [run_case(args, case, out_dir) for case in CASES]
    hard_cases = cases
    stress_cases = [case for case in cases if case["stress"]]

    metric_limit = schwarzschild_limit_metric_check()
    trajectory_limit = schwarzschild_kerr_a0_trajectory_check()
    photon_sphere = schwarzschild_photon_sphere_check()
    contract_notes = [
        "Carter Q drift is hard-gated for stable non-stress Kerr probes.",
        "Schwarzschild-vs-Kerr(a=0) metric identity and calibrated Hamiltonian trajectory agreement are hard gates.",
        "Schwarzschild photon-sphere orbit and a calibrated 3x3 image-plane near-critical grid are hard gates.",
    ]
    contract_gaps: list[str] = []
    report = {
        "phase": "Phase 2 / L0 geodesic scalar baseline",
        "passed": all(case["harness_passed"] for case in hard_cases)
        and metric_limit["passed"]
        and trajectory_limit["passed"]
        and photon_sphere["passed"],
        "contract_notes": contract_notes,
        "contract_gaps": contract_gaps,
        "critical_grid": {
            "description": "3x3 image-plane near-critical stress grid around the central critical stencil.",
            "center_pixel": {"x": 160, "y": 90},
            "offsets": [{"dx": dx, "dy": dy} for dx, dy in CRITICAL_GRID_OFFSETS],
            "case_count": len(CRITICAL_GRID_OFFSETS),
            "step_size": 0.002,
            "max_steps": 500,
        },
        "schwarzschild_limit_metric": metric_limit,
        "schwarzschild_kerr_a0_trajectory": trajectory_limit,
        "schwarzschild_photon_sphere": photon_sphere,
        "cases": cases,
        "summary": {
            "hard_case_count": len(hard_cases),
            "hard_cases_passed": sum(1 for case in hard_cases if case["harness_passed"]),
            "stress_case_count": len(stress_cases),
        },
    }

    report_path = out_dir / "geodesic_scalar_baseline.json"
    report_path.write_text(json.dumps(report, indent=2, sort_keys=True), encoding="utf-8")
    print(json.dumps(report, indent=2, sort_keys=True))
    print(f"report={report_path}")

    should_fail = not report["passed"] or (args.fail_on_contract_gaps and contract_gaps)
    if should_fail:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
