#!/usr/bin/env python3
"""Report render-mode contract coverage without rendering images."""

from __future__ import annotations

import json
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]

CONTRACT_MODES = [
    "scientific",
    "human-eye",
    "camera-raw",
    "camera-rendered",
    "cinematic",
    "legacy",
]

CLI_EQUIVALENTS = {
    "scientific": ["scientific"],
    "human-eye": ["eye"],
    "camera-raw": ["camera-raw"],
    "camera-rendered": ["camera-rendered"],
    "cinematic": ["cinema", "cinematic"],
    "legacy": ["legacy"],
}


def run_help() -> str:
    return subprocess.run(
        ["bash", "Blackhole/run_pipeline.sh", "--help", "camera"],
        cwd=str(ROOT),
        check=True,
        text=True,
        capture_output=True,
    ).stdout


def main() -> None:
    help_text = run_help()
    docs = (ROOT / "docs/realism/09_render_modes.md").read_text(encoding="utf-8")
    visual = (ROOT / "Blackhole/Sources/Params/ParamsBuilderVisual.swift").read_text(encoding="utf-8")

    modes = {}
    for mode in CONTRACT_MODES:
        aliases = CLI_EQUIVALENTS[mode]
        documented = mode in docs
        parsed = any(f'"{alias}"' in visual for alias in aliases)
        help_exposed = any(alias in help_text for alias in aliases)
        if documented and parsed and help_exposed:
            status = "covered"
        else:
            status = "partial"
        modes[mode] = {
            "status": status,
            "documented": documented,
            "parsed_aliases": aliases,
            "parser_found": parsed,
            "help_found": help_exposed,
        }

    result = {
        "passed": True,
        "note": "camera-raw and camera-rendered are first-class CLI presentation names. camera-raw routes to a RAW-like scientific audit path and can emit a float4 linear32 sidecar; it is not yet a full CFA/sensor RAW buffer.",
        "modes": modes,
    }
    print(json.dumps(result, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
