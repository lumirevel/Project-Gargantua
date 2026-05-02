# Plausible Cinematic Disk Goal Completion Report V1

Date: 2026-05-02

Branch: `codex/integration/physics-camera-v1-legacy-recovery`

## Summary

This pass made `physics-constrained-cinematic-disk-v1` a distinct production source profile rather than a practical alias of `canonical-visible-disk-v1`. The model now has ABI-carried source controls, profile 6 source logic, source diagnostics, A/B validation, and science-gated candidate search.

Promotion readiness: **ready with caveats**.

## Files Changed

Core source / ABI / params:

- `Blackhole/Metal/Compose/helpers.metalh`
- `Blackhole/Metal/gr_math.metal`
- `Blackhole/Sources/Core/ABI/PackedParams.swift`
- `Blackhole/Sources/Core/Config/ResolvedRenderConfig.swift`
- `Blackhole/Sources/Params/ParamsBuilder.swift`
- `Blackhole/Sources/Params/ParamsBuilderPacking.swift`
- `Blackhole/Sources/Params/ParamsBuilderSummary.swift`
- `Blackhole/Sources/Params/ParamsBuilderVisual.swift`
- `Blackhole/Sources/Render/Core/RenderResourcePolicy.swift`
- `Blackhole/run_pipeline.sh`

Scripts:

- `scripts/validate_physics_constrained_cinematic_disk.py`
- `scripts/search_plausible_cinematic_disk.py`

Docs:

- `docs/realism/plausible_cinematic_disk_goal_v1.md`
- `docs/realism/physics_constrained_cinematic_disk_v1.md`
- `docs/realism/plausible_cinematic_disk_search_v1.md`
- `docs/realism/plausible_cinematic_disk_goal_completion_report_v1.md`

## Model Distinction From Canonical

- `canonical-visible-disk-v1` remains `realismProfileID = 5`.
- `physics-constrained-cinematic-disk-v1` now maps to `realismProfileID = 6`.
- Profile 6 has independent source controls and source-field diagnostics through `pcdSourceA/B/C`.
- Extreme A/B tests prove source diagnostics and final RGB differ from the no-structure baseline.

## ABI Summary

Validated packed layout:

```text
PackedParams.layout size=672 stride=672 align=16
pcdSourceA offset=624
pcdSourceB offset=640
pcdSourceC offset=656
```

## A/B Test Results

Command:

```bash
python3 scripts/validate_physics_constrained_cinematic_disk.py \
  --width 160 \
  --height 90 \
  --out-dir /private/tmp/bh_pcd_goal_validation \
  --no-build
```

Outputs:

- `/private/tmp/bh_pcd_goal_validation/ab_sheet.png`
- `/private/tmp/bh_pcd_goal_validation/ab_metrics.json`
- `/private/tmp/bh_pcd_goal_validation/ab_report.md`

| Gate | Value | Pass |
| --- | ---: | --- |
| source activity/emissivity/density RMSE | max 0.178328 | yes |
| no/high final RGB RMSE | 0.012572 | yes |
| high/low optical-depth RMSE | 0.185753 | yes |
| high/low transfer-saturation mean diff | 0.055730 | yes |
| high-Doppler asymmetry ratio | 37.201658 | yes |

## Search Results

Command:

```bash
python3 scripts/search_plausible_cinematic_disk.py \
  --count 12 \
  --top 3 \
  --width 160 \
  --height 90 \
  --out-dir /private/tmp/bh_pcd_goal_search \
  --no-build
```

Outputs:

- `/private/tmp/bh_pcd_goal_search/search_report.json`
- `/private/tmp/bh_pcd_goal_search/top_candidates.json`
- `/private/tmp/bh_pcd_goal_search/best_params.json`
- `/private/tmp/bh_pcd_goal_search/top_candidates_sheet.png`

| Metric | Value |
| --- | ---: |
| evaluated candidates | 12 |
| science-passing candidates | 9 |
| top candidates | 3 |
| search passed | true |

Top candidates:

| Rank | Candidate | Score | Params | Score JSON |
| ---: | --- | ---: | --- | --- |
| 1 | `camd_10` | 0.865077 | `/private/tmp/bh_pcd_goal_search/camd_10/params.json` | `/private/tmp/bh_pcd_goal_search/camd_10/score.json` |
| 2 | `camd_01` | 0.861372 | `/private/tmp/bh_pcd_goal_search/camd_01/params.json` | `/private/tmp/bh_pcd_goal_search/camd_01/score.json` |
| 3 | `camd_06` | 0.828638 | `/private/tmp/bh_pcd_goal_search/camd_06/params.json` | `/private/tmp/bh_pcd_goal_search/camd_06/score.json` |

## Validation Commands

```bash
bash -n Blackhole/run_pipeline.sh
python3 -m py_compile scripts/validate_physics_constrained_cinematic_disk.py scripts/search_plausible_cinematic_disk.py
xcodebuild -project Blackhole.xcodeproj -scheme Blackhole -configuration Release -derivedDataPath /private/tmp/ProjectGargantuaPcdGoalDerivedData build
/private/tmp/ProjectGargantuaPcdGoalDerivedData/Build/Products/Release/Blackhole --validate-packed-abi --print-packed-layout
BH_DERIVED_DATA_PATH=/private/tmp/ProjectGargantuaPcdGoalDerivedData bash Blackhole/run_pipeline.sh --source-model physics-constrained-cinematic-disk-v1 --quality preview --presentation scientific --look linear --width 160 --height 90 --output /private/tmp/bh_pcd_goal_validation/preview.png --no-build
python3 scripts/validate_physics_constrained_cinematic_disk.py --width 160 --height 90 --out-dir /private/tmp/bh_pcd_goal_validation --no-build
python3 scripts/search_plausible_cinematic_disk.py --count 12 --top 3 --width 160 --height 90 --out-dir /private/tmp/bh_pcd_goal_search --no-build
git diff --check
```

## Pass / Fail Table

| Check | Result |
| --- | --- |
| run pipeline shell syntax | pass |
| scripts py_compile | pass |
| Release build | pass |
| packed ABI validation | pass |
| profile 6 preview render | pass |
| A/B source diagnostics | pass |
| A/B final RGB response | pass |
| A/B opacity response | pass |
| A/B Doppler response | pass |
| 12-candidate search | pass |
| 3 distinct science-passing top candidates | pass |

## Remaining Caveats

- Profile 6 remains a labeled physics-constrained surrogate, not real GRMHD.
- The local optical-depth/saturation proxy is not a full vertical transfer solve.
- The best candidates are low-resolution previews; final candidate selection still needs higher-resolution review and source diagnostic sheets.
- Existing dirty/untracked files from prior sessions remain in the worktree and should be staged selectively.

## Next Recommended Task

Render the top three candidates at medium/high resolution with the same source diagnostics, then choose one candidate for scientific/eye/cinema downstream interpretation without changing source morphology per presentation mode.
