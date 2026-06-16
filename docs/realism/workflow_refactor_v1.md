# Workflow Refactor V1

Date: 2026-06-17

## Scope

This is a maintenance refactor for the GUI/CLI option workflow. It does not
change physics, observer math, Metal buffers, source models, or presentation
defaults.

## Problem

The renderer has a broad CLI and a growing GUI. Before this refactor, the same
command-surface rules were spread across:

- `tools/GargantuaLauncher/GargantuaLauncher.swift`
- `scripts/validate_gui_command_matrix.py`
- `scripts/validate_gui_option_manifest.py`
- static-token validators that assumed one launcher Swift file

That made simple option changes risky: adding a source or render intent could
require manual edits in several places.

## New Boundary

The GUI now separates:

```text
manifest data
  -> launcher models and repository path resolution
  -> pure render command planner
  -> SwiftUI state/view
  -> process execution
```

Swift files:

- `LauncherModels.swift`: manifest models, fallback entries, repository path
  resolution, observer/quality/aspect enums.
- `RenderCommandPlanner.swift`: side-effect-free conversion from GUI state to
  CLI arguments and shell preview.
- `GargantuaLauncher.swift`: SwiftUI state, controls, process execution, and
  logging.

Python validation:

- `scripts/gargantua_gui_contract.py` owns the shared manifest path, required
  GUI IDs, render-intent matrix, RAW-like audit args, and command builder used
  by GUI validators.

## Maintenance Rule

When adding or changing a GUI source or render intent:

1. Update `docs/realism/gui_option_manifest_v1.json`.
2. Update `RenderCommandPlanner.swift` only if a new intent changes command
   construction.
3. Update `gargantua_gui_contract.py` if the validator matrix needs to reflect
   the same construction rule.
4. Run the GUI validators before merging.

Do not add renderer physics, Metal kernels, or source-model tuning to the GUI
target. The launcher remains a thin command generator.

## Validation

Minimum checks for this workflow boundary:

```bash
python3 -m py_compile scripts/gargantua_gui_contract.py scripts/validate_gui_command_matrix.py scripts/validate_gui_option_manifest.py scripts/validate_gui_primary_target.py scripts/validate_scientific_raw_purity.py
python3 scripts/validate_gui_option_manifest.py
python3 scripts/validate_gui_command_matrix.py
python3 scripts/validate_gui_primary_target.py
python3 scripts/validate_scientific_raw_purity.py
xcodebuild -project Blackhole.xcodeproj -scheme GargantuaLauncher -configuration Debug -derivedDataPath /tmp/BlackholeLauncherRefactorDD build
```
