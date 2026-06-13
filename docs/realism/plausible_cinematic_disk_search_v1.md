# Plausible Cinematic Disk Search V1

Date: 2026-05-02

## Purpose

`scripts/search_plausible_cinematic_disk.py` searches `physics-constrained-cinematic-disk-v1` as a source-model parameter space. It is not a beauty-only optimizer. The search first applies science gates, then ranks passing and non-duplicate candidates by aesthetic metrics.

Generated images and JSON are written outside the repository, under `/private/tmp` by default.

## Command

```bash
python3 scripts/search_plausible_cinematic_disk.py \
  --count 12 \
  --top 3 \
  --width 160 \
  --height 90 \
  --out-dir /private/tmp/bh_pcd_goal_search \
  --no-build
```

## Sampled Parameters

The search samples physically meaningful controls:

- `pcd_density_exp`
- `pcd_emissivity_scale`
- `pcd_opacity_scale`
- `pcd_seed`
- `pcd_structure_scale`
- `pcd_spiral_amp`
- `pcd_spiral_pitch`
- `pcd_clump_contrast`
- `pcd_hot_crescent`
- `temperature_scale` / `--teff-T0`
- `temp_exponent` / `--teff-p`
- `color_factor` / `--fcol`
- `disk_turbulence`
- `disk_time`
- `orbital_boost`
- `photosphere_thickness`
- camera preset among `balanced`, `realistic`, `thin-disk`, and minority `eht`

## Per-Candidate Outputs

Each candidate directory contains:

- `params.json`
- `command.json`
- `preview.png`
- `score.json`
- minimal diagnostics: `activity`, `emissivity-pre-transfer`, `optical-depth`, `transfer-saturation`

The selected top candidates also receive full diagnostics:

- `density`
- `temperature`
- `opacity`
- `spiral`
- `clump`
- `hot-crescent`
- `g`
- `beaming`
- `raw-radiance`

Search-level outputs:

- `/private/tmp/bh_pcd_goal_search/search_report.json`
- `/private/tmp/bh_pcd_goal_search/top_candidates.json`
- `/private/tmp/bh_pcd_goal_search/best_params.json`
- `/private/tmp/bh_pcd_goal_search/top_candidates_sheet.png`

## Science Gate

A candidate must satisfy source/transfer plausibility before final ranking:

- nonzero but bounded active disk fraction
- source diagnostics show activity/emissivity structure
- optical-depth / transfer-saturation are not globally saturated
- black background is preserved
- saturated pixel ratio is bounded
- final RGB differs from the no-structure reference when source diagnostics differ

## Score Caps And Duplicate Rejection

The score penalizes or caps:

- low azimuthal variance
- globally smooth disks
- near-duplicate candidates
- source structure that disappears in final RGB
- excessive transfer saturation
- excessive clipping or bloom washout

Smooth boring disks cannot score above `0.90`. If fewer than three distinct science-passing candidates are found from 12 samples, the script automatically expands to 24 samples before reporting failure.

## Current Validation Result

Search output: `/private/tmp/bh_pcd_goal_search/search_report.json`

| Metric | Value |
| --- | ---: |
| evaluated candidates | 12 |
| science-passing candidates | 9 |
| top candidate count | 3 |
| passed | true |

Top candidates:

| Rank | Candidate | Score | Params | Preview |
| ---: | --- | ---: | --- | --- |
| 1 | `camd_10` | 0.865077 | `/private/tmp/bh_pcd_goal_search/camd_10/params.json` | `/private/tmp/bh_pcd_goal_search/camd_10/preview.png` |
| 2 | `camd_01` | 0.861372 | `/private/tmp/bh_pcd_goal_search/camd_01/params.json` | `/private/tmp/bh_pcd_goal_search/camd_01/preview.png` |
| 3 | `camd_06` | 0.828638 | `/private/tmp/bh_pcd_goal_search/camd_06/params.json` | `/private/tmp/bh_pcd_goal_search/camd_06/preview.png` |

## Limitations

The search still evaluates low-resolution previews. Top candidates must be re-rendered at higher resolution with source diagnostics before being treated as final imagery.
