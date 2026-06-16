#!/usr/bin/env python3
"""Phase 3 redshift and invariant-intensity scalar baseline.

This is a fast contract check for the transfer equations and implementation
surface. It does not render and does not modify source or presentation paths.
"""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--out", default="/private/tmp/bh_transfer_scalar_baseline.json")
    return p.parse_args()


def redshift_from_dot(obs_dot_k: float, emit_dot_k: float) -> float:
    return obs_dot_k / emit_dot_k


def observed_intensity(i_emit: float, g: float) -> float:
    return (g ** 3) * i_emit


def invariant_ratio(i_nu: float, nu: float) -> float:
    return i_nu / max(nu ** 3, 1e-300)


def implementation_evidence() -> dict[str, Any]:
    files = {
        "disk_models": ROOT / "Blackhole" / "Metal" / "disk_models.metal",
        "spectrum_visible": ROOT / "Blackhole" / "Metal" / "spectrum_visible.metal",
        "volume_rt": ROOT / "Blackhole" / "Metal" / "volume_rt.metal",
        "compose_helpers": ROOT / "Blackhole" / "Metal" / "Compose" / "helpers.metalh",
        "params_visual": ROOT / "Blackhole" / "Sources" / "Params" / "ParamsBuilderVisual.swift",
    }
    tokens = {
        "disk_models": [
            "g = (u_obs",
            "disk_schwarzschild_direct_gfactor",
            "disk_kerr_flow_gfactor",
        ],
        "spectrum_visible": [
            "I_nu / nu^3",
            "I_nu_obs = g^3",
        ],
        "volume_rt": [
            "g_factor",
            "IVisNu",
        ],
        "compose_helpers": [
            "I_nu/nu^3",
        ],
        "params_visual": [
            "g-factor",
            "redshift",
            "beaming",
        ],
    }
    evidence: dict[str, Any] = {}
    for key, path in files.items():
        text = path.read_text(encoding="utf-8")
        evidence[key] = {
            "path": str(path),
            "tokens": {token: token in text for token in tokens[key]},
        }
    return evidence


def analytic_cases() -> list[dict[str, Any]]:
    nu_emit = 5.0e14
    i_emit = 2.5
    cases: list[dict[str, Any]] = []

    static_g = redshift_from_dot(-1.0, -1.0)
    static_i_obs = observed_intensity(i_emit, static_g)
    cases.append(
        {
            "name": "static_emitter_static_observer",
            "g": static_g,
            "i_emit": i_emit,
            "i_obs": static_i_obs,
            "invariant_emit": invariant_ratio(i_emit, nu_emit),
            "invariant_obs": invariant_ratio(static_i_obs, static_g * nu_emit),
            "gate": abs(static_g - 1.0) < 1e-12 and abs(static_i_obs - i_emit) < 1e-12,
        }
    )

    beta = 0.35
    gamma = 1.0 / math.sqrt(1.0 - beta * beta)
    g_approach = 1.0 / (gamma * (1.0 - beta))
    g_recede = 1.0 / (gamma * (1.0 + beta))
    for name, g in (("approaching_emitter", g_approach), ("receding_emitter", g_recede)):
        i_obs = observed_intensity(i_emit, g)
        cases.append(
            {
                "name": name,
                "beta": beta,
                "g": g,
                "i_emit": i_emit,
                "i_obs": i_obs,
                "invariant_emit": invariant_ratio(i_emit, nu_emit),
                "invariant_obs": invariant_ratio(i_obs, g * nu_emit),
                "gate": abs(invariant_ratio(i_emit, nu_emit) - invariant_ratio(i_obs, g * nu_emit))
                / invariant_ratio(i_emit, nu_emit)
                < 1e-12,
            }
        )

    cases.append(
        {
            "name": "doppler_ordering",
            "g_approach": g_approach,
            "g_recede": g_recede,
            "i_approach": observed_intensity(i_emit, g_approach),
            "i_recede": observed_intensity(i_emit, g_recede),
            "gate": g_approach > 1.0 > g_recede
            and observed_intensity(i_emit, g_approach) > observed_intensity(i_emit, g_recede),
        }
    )
    return cases


def main() -> None:
    args = parse_args()
    cases = analytic_cases()
    evidence = implementation_evidence()
    missing_tokens = [
        f"{file_key}:{token}"
        for file_key, row in evidence.items()
        for token, present in row["tokens"].items()
        if not present
    ]
    report = {
        "phase": "Phase 3 / L2 transfer scalar baseline",
        "equations": {
            "redshift": "g = nu_obs / nu_emit = (k_mu u_obs^mu) / (k_mu u_emit^mu)",
            "intensity": "I_nu_obs = g^3 I_nu_emit(nu_obs / g)",
            "invariant": "I_nu / nu^3",
        },
        "analytic_cases": cases,
        "implementation_evidence": evidence,
        "missing_implementation_tokens": missing_tokens,
        "passed": all(case["gate"] for case in cases) and not missing_tokens,
        "contract_gaps": [
            "This fast baseline proves equations and implementation surface tokens, not a rendered redshift map.",
            "Renderer-produced g-factor and beaming map thresholds are covered separately by scripts/validate_transfer_gfactor_maps.py.",
            "A no-flow renderer fixture is covered separately by scripts/validate_transfer_static_renderer_fixture.py.",
            "A true same-tetrad static-emitter/static-observer renderer fixture is still needed for a full Phase 3 hard gate.",
        ],
    }
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(report, indent=2, sort_keys=True), encoding="utf-8")
    print(json.dumps(report, indent=2, sort_keys=True))
    print(f"report={out}")
    if not report["passed"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
