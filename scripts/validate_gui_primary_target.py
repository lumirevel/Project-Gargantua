#!/usr/bin/env python3
"""Validate the contract-aware GUI is promoted to a primary macOS app target."""

from __future__ import annotations

import json
import re
from pathlib import Path

from gargantua_gui_contract import launcher_sources_text


ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "Blackhole.xcodeproj" / "project.pbxproj"
OUT = Path("/private/tmp/bh_gui_primary_target.json")


def find_block(text: str, object_id: str) -> str:
    pattern = re.compile(rf"\n\t\t{re.escape(object_id)} /\* .*? \*/ = \{{(.*?)\n\t\t\}};", re.S)
    match = pattern.search(text)
    return match.group(1) if match else ""


def main() -> None:
    text = PROJECT.read_text(encoding="utf-8")
    launcher_text = launcher_sources_text()
    target_id = "D1A000000000000000000009"
    sources_id = "D1A000000000000000000007"
    resources_id = "D1A000000000000000000008"
    target_block = find_block(text, target_id)
    sources_block = find_block(text, sources_id)
    resources_block = find_block(text, resources_id)

    checks = {
        "app_target_exists": "D1A000000000000000000009 /* GargantuaLauncher */" in text,
        "product_type_application": 'productType = "com.apple.product-type.application";' in target_block,
        "source_file_referenced": "tools/GargantuaLauncher/GargantuaLauncher.swift" in text,
        "launcher_model_file_referenced": "tools/GargantuaLauncher/LauncherModels.swift" in text,
        "command_planner_file_referenced": "tools/GargantuaLauncher/RenderCommandPlanner.swift" in text,
        "manifest_file_referenced": "docs/realism/gui_option_manifest_v1.json" in text,
        "launcher_in_sources": "GargantuaLauncher.swift in Sources" in sources_block,
        "launcher_models_in_sources": "LauncherModels.swift in Sources" in sources_block,
        "command_planner_in_sources": "RenderCommandPlanner.swift in Sources" in sources_block,
        "manifest_in_resources": "gui_option_manifest_v1.json in Resources" in resources_block,
        "generated_infoplist": "GENERATE_INFOPLIST_FILE = YES;" in text,
        "bundle_identifier": "local.project-gargantua.GargantuaLauncher" in text,
        "cli_target_still_tool": 'C0152EA82F47E42B00DEB017 /* Blackhole */' in text
        and 'productType = "com.apple.product-type.tool";' in text,
        "render_uses_absolute_pipeline_path": "ProjectPaths.runPipelineURL.path" in launcher_text,
        "render_cwd_is_repository_root": "process.currentDirectoryURL = plan.repositoryRoot" in launcher_text,
        "render_exports_project_root": 'environment["BH_PROJECT_ROOT"] = plan.repositoryRoot.path' in launcher_text,
        "render_has_gui_path_fallback": 'environment["PATH"] = guiPath' in launcher_text
        and "/Applications/Xcode.app/Contents/Developer/usr/bin" in launcher_text,
        "render_process_is_retained": "private var runningProcess: Process?" in launcher_text
        and "runningProcess = process" in launcher_text
        and "self?.runningProcess = nil" in launcher_text,
        "render_can_be_stopped": "func stopRender()" in launcher_text
        and 'Button("Stop")' in launcher_text,
        "fallback_includes_restored_legacy_models": "legacy-perlin-classic" in launcher_text
        and "legacy-perlin-ec7" in launcher_text
        and "perlin-classic" in launcher_text
        and "perlin-ec7" in launcher_text,
        "fallback_includes_image_legacy_recipes": "legacy-bh-finish-grmhd" in launcher_text
        and "legacy-thin-disk-preset-default" in launcher_text,
    }

    forbidden_target_tokens = [
        "volume_rt.metal",
        "helpers.metalh",
        "RenderExecution.swift",
        "ParamsBuilder.swift",
    ]
    checks["no_renderer_files_in_gui_target"] = not any(
        token in target_block or token in sources_block or token in resources_block
        for token in forbidden_target_tokens
    )

    failures = [name for name, passed in checks.items() if not passed]
    report = {
        "phase": "GUI primary target",
        "passed": not failures,
        "failures": failures,
        "checks": checks,
        "target": "GargantuaLauncher",
        "contract": [
            "GUI is a separate macOS app target.",
            "GUI bundles the option manifest.",
            "GUI target does not compile renderer or Metal physics files.",
            "Blackhole CLI target remains a tool.",
            "GUI render action uses an absolute run_pipeline path from the resolved repository root.",
            "GUI retains the running Process until termination and exposes a Stop control.",
            "GUI fallback keeps restored legacy Perlin Classic/F552 and EC7 options visible.",
            "GUI fallback keeps recovered bh_finish and thin_disk_preset_default recipes visible.",
        ],
    }
    OUT.write_text(json.dumps(report, indent=2, sort_keys=True), encoding="utf-8")
    print(json.dumps({k: v for k, v in report.items() if k != "checks"}, indent=2, sort_keys=True))
    print(f"report={OUT}")
    if failures:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
