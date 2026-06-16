#!/usr/bin/env python3
"""Validate the GUI option manifest against CLI/docs contracts."""

from __future__ import annotations

import json
from pathlib import Path

from gargantua_gui_contract import (
    MANIFEST,
    REQUIRED_INTENTS,
    REQUIRED_SOURCE_IDS,
    VALID_STATUS,
    launcher_sources_text,
)

ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    failures: list[str] = []
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    docs = (ROOT / "docs" / "source_models.md").read_text(encoding="utf-8")
    launcher = launcher_sources_text()
    run_pipeline = (ROOT / "Blackhole" / "run_pipeline.sh").read_text(encoding="utf-8")

    if manifest.get("schemaVersion") != 1:
        failures.append("schemaVersion must be 1")

    sources = manifest.get("sourceModels", [])
    intents = manifest.get("renderIntents", [])
    source_by_id = {row.get("id"): row for row in sources}
    intent_ids = {row.get("id") for row in intents}
    status_counts = {status: 0 for status in VALID_STATUS}

    for source_id in REQUIRED_SOURCE_IDS:
        if source_id not in source_by_id:
            failures.append(f"manifest missing source {source_id}")

    for intent_id in REQUIRED_INTENTS:
        if intent_id not in intent_ids:
            failures.append(f"manifest missing render intent {intent_id}")

    for row in sources:
        source_id = row.get("id", "")
        status = row.get("status", "")
        args = row.get("args", [])
        if status not in VALID_STATUS:
            failures.append(f"{source_id}: invalid status {status!r}")
        else:
            status_counts[status] += 1
        if not isinstance(args, list) or not args:
            failures.append(f"{source_id}: args must be a non-empty list")
        if row.get("requiresDiskHDF5"):
            default_hdf5 = row.get("defaultDiskHDF5", "")
            if not isinstance(default_hdf5, str) or not default_hdf5:
                failures.append(f"{source_id}: requiresDiskHDF5 sources must define defaultDiskHDF5")
            if status not in {"diagnostic", "production-candidate", "legacy"}:
                failures.append(f"{source_id}: HDF5-backed source must be diagnostic, production-candidate, or legacy")
        if source_id.startswith("legacy-"):
            if "--disk-model" not in args and "--science-regime" not in args:
                failures.append(f"{source_id}: legacy source must use --disk-model or --science-regime")
            if status != "legacy":
                failures.append(f"{source_id}: legacy source must have legacy status")
            if "--science-regime" in args:
                idx = args.index("--science-regime")
                if idx + 1 >= len(args) or args[idx + 1] != source_id:
                    failures.append(f"{source_id}: legacy science-regime source must pass --science-regime {source_id}")
                if source_id not in run_pipeline:
                    failures.append(f"{source_id}: missing from run_pipeline.sh")
        else:
            if args[:2] != ["--source-model", source_id]:
                failures.append(f"{source_id}: public source args must start with --source-model <id>")
            if source_id not in docs:
                failures.append(f"{source_id}: missing from docs/source_models.md")
            if source_id not in run_pipeline:
                failures.append(f"{source_id}: missing from run_pipeline.sh")
            if status == "legacy":
                failures.append(f"{source_id}: non-legacy source cannot have legacy status")

    if status_counts["recommended"] < 1:
        failures.append("manifest must expose at least one recommended source")
    if status_counts["legacy"] < 1:
        failures.append("manifest must preserve at least one legacy reproduction source")
    if status_counts["surrogate"] < 1 and status_counts["diagnostic"] < 1:
        failures.append("manifest must expose at least one clearly labeled diagnostic/surrogate source")

    for token in [
        "gui_option_manifest_v1.json",
        "JSONDecoder",
        "manifestSearchPaths",
        "Section(\"Recommended\")",
        "Section(\"Diagnostics\")",
        "Section(\"Legacy\")",
        "isCameraAdjustmentEnabled",
        "requiresDiskHDF5",
        "--disk-hdf5",
    ]:
        if token not in launcher:
            failures.append(f"GargantuaLauncher.swift missing manifest token {token}")

    if failures:
        print("\n".join(failures))
        raise SystemExit(1)

    print("GUI option manifest validation passed")


if __name__ == "__main__":
    main()
