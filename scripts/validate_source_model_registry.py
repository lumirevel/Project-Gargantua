#!/usr/bin/env python3
"""Check source-model registry alignment across docs, help, and CLI validation."""

from __future__ import annotations

import re
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]

PUBLIC_OR_CANDIDATE = [
    "canonical-visible-disk-v1",
    "cinematic-physical-disk-v1",
    "physics-constrained-cinematic-disk-v1",
    "thin-disk-visible-reference",
    "static-transfer-reference-v1",
    "grmhd-surrogate-disk-v1",
    "grmhd-hot-flow-diagnostic",
    "grmhd-temperature-flow-diagnostic",
]

VALIDATION_CANDIDATES = [
    "grmhd-plasma-fluctuation-candidate",
    "grmhd-visible-disk-skin-candidate",
    "thin-luminous-layer-candidate",
]

SOURCE_TEMPLATE_FIELDS = [
    "Assumptions",
    "Inputs",
    "Outputs",
    "Known limitations",
    "Allowed render modes",
    "Validation scenes",
    "Forbidden hacks",
]


def run_help() -> str:
    return subprocess.run(
        ["bash", "Blackhole/run_pipeline.sh", "--help", "source-models"],
        cwd=str(ROOT),
        check=True,
        text=True,
        capture_output=True,
    ).stdout


def main() -> None:
    failures: list[str] = []
    help_text = run_help()
    docs = (ROOT / "docs/source_models.md").read_text(encoding="utf-8")
    cli_validator = (ROOT / "scripts/validate_cli_surface.py").read_text(encoding="utf-8")
    run_pipeline = (ROOT / "Blackhole/run_pipeline.sh").read_text(encoding="utf-8")

    for model in PUBLIC_OR_CANDIDATE:
        if model not in help_text:
            failures.append(f"source-model help missing {model}")
        if model not in docs:
            failures.append(f"docs/source_models.md missing {model}")
        if model not in cli_validator:
            failures.append(f"validate_cli_surface.py missing {model}")
        if model not in run_pipeline:
            failures.append(f"run_pipeline.sh missing {model}")

    for model in VALIDATION_CANDIDATES:
        if model not in help_text:
            failures.append(f"source-model help missing validation candidate {model}")
        if model not in run_pipeline:
            failures.append(f"run_pipeline.sh missing validation candidate {model}")

    status_labels = ["recommended", "production-candidate", "surrogate", "diagnostic", "legacy"]
    for label in status_labels:
        if label not in docs:
            failures.append(f"docs/source_models.md missing status label {label}")

    documented_models = set(re.findall(r"`([a-z0-9][a-z0-9-]+-v1|thin-disk-visible-reference|grmhd-[a-z0-9-]+-diagnostic)`", docs))
    missing_doc_rows = sorted(set(PUBLIC_OR_CANDIDATE) - documented_models)
    if missing_doc_rows:
        failures.append("docs/source_models.md does not document rows for: " + ", ".join(missing_doc_rows))

    if "## Source Model Contract Matrix" not in docs:
        failures.append("docs/source_models.md missing Source Model Contract Matrix")
        matrix = ""
    else:
        matrix = docs.split("## Source Model Contract Matrix", 1)[1].split("\n## ", 1)[0]

    for field in SOURCE_TEMPLATE_FIELDS:
        if field not in matrix:
            failures.append(f"source contract matrix missing template field {field!r}")

    for model in PUBLIC_OR_CANDIDATE:
        row_match = re.search(rf"^\| `{re.escape(model)}` \|(.+)$", matrix, re.MULTILINE)
        if not row_match:
            failures.append(f"source contract matrix missing row for {model}")
            continue
        cells = [cell.strip() for cell in row_match.group(0).strip().strip("|").split("|")]
        if len(cells) != len(SOURCE_TEMPLATE_FIELDS) + 1:
            failures.append(f"{model}: source contract row must have {len(SOURCE_TEMPLATE_FIELDS) + 1} cells")
            continue
        for field, cell in zip(SOURCE_TEMPLATE_FIELDS, cells[1:]):
            if len(cell) < 12:
                failures.append(f"{model}: source contract field {field!r} is too thin")
        if "scientific" not in cells[5] or "camera-raw" not in cells[5]:
            failures.append(f"{model}: allowed render modes must include scientific and camera-raw")

    if failures:
        print("\n".join(failures))
        raise SystemExit(1)

    print("source model registry validation passed")


if __name__ == "__main__":
    main()
