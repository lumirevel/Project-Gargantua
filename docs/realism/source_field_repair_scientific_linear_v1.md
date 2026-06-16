# Source Field Repair: Scientific Linear v1

## Purpose

`physics-constrained-cinematic-disk-v1` still looked cloudy and spatially uniform even with `--presentation scientific --look linear`. That makes the primary fault source/transfer-side, not eye/cinema/tone mapping/bloom/glare. This pass repairs the profile-6 source fields so physical controls visibly affect source diagnostics and the scientific-linear render.

## Path Actually Taken

Command family:

```bash
BH_DERIVED_DATA_PATH=/private/tmp/ProjectGargantuaSourceRepairDerivedData \
  bash Blackhole/run_pipeline.sh \
  --source-model physics-constrained-cinematic-disk-v1 \
  --presentation scientific \
  --look linear \
  --quality preview
```

Resolved pipeline summary from `run_pipeline.sh`:

- `source_model`: `physics-constrained-cinematic-disk-v1`
- `science_regime`: `physics-constrained-cinematic-disk-v1`
- `presentation_mode`: `scientific`
- `look`: `linear`
- `pipeline_mode`: `gpu-only`
- `gpu_strategy`: `canonical-gpu-compose`
- `metric`: default `schwarzschild`, unless overridden by the high-Doppler A/B preset.

Swift/Metal path:

- `run_pipeline.sh` maps the source model to `--realism-profile physics-constrained-cinematic-disk-v1`.
- `ParamsBuilderVisual.swift` maps that profile to `realismProfileID = 6`.
- `ParamsBuilderPacking.swift` packs `pcdSourceA/B/C` into `PackedParams`.
- `gr_math.metal` mirrors `pcdSourceA/B/C` in Metal `Params`.
- `Compose/helpers.metalh` uses `C.realismProfile == 6u` inside the thin-visible-reference source path.
- Ray/disk intersection, visible blackbody/graybody conversion, and g-factor transfer remain shared with the thin visible reference path.
- Source morphology is now profile-6-specific through density/emissivity/opacity/activity/spiral/clump/hot-crescent fields.

This is not a pure standalone disk-intersection kernel, but it is no longer merely canonical profile 5 with identical source morphology: profile 6 has distinct source fields and branch budget.

## Why It Was Still Hazy / Uniform

The previous profile-6 implementation technically added source fields, but the visible final image remained weak because:

1. `densityProxy` was mostly radial-only, so high-structure controls did not strongly alter the density diagnostic.
2. `hotCrescentProxy` was computed after it was already used by part of the positive-heating lift, reducing its effective impact.
3. Most structure entered through the skin branch fraction, while the photospheric source flux stayed close to the clean thin-disk body.
4. The visible blackbody path compresses moderate temperature/emissivity differences, so source perturbations must affect emissivity/radiance before final scientific-linear display.
5. `--no-build` can accidentally use a stale `.DerivedData` binary; the initial failed validation did exactly that and reported that profile 6 was unsupported. Validation now pins `BH_DERIVED_DATA_PATH` to the rebuilt binary.

## Source Field Changes

Changed file:

- `Blackhole/Metal/Compose/helpers.metalh`
- `Blackhole/run_pipeline.sh`

Profile-6-only source changes:

- `pcdDensityBase` remains radial/outer-tapered but now becomes structured density:

```text
pcdDensity = pcdDensityBase * (1 + 0.34*spiral + 0.42*clump + 0.16*hotCrescent)
```

- `spiralProxy` is a positive logarithmic spiral wave in disk coordinates:

```text
spiralRaw = pow(0.5 + 0.5*cos(phi - OmegaK*t - pitch*log(r/rIn) + seedPhase), 1.35)
spiralProxy = spiralAmp * spiralRaw * radialGate
```

- `clumpProxy` is a positive disk-coordinate heating packet support:

```text
clumpProxy = clumpContrast * (0.58*heat.cloud + 0.42*heat.filament) * radialGate
```

- `hotCrescentProxy` is now computed before source lift and tied to inner radius and g-factor support:

```text
hotCrescentProxy = hotCrescent * innerWeight * radialGate * smoothstep(0.94, 1.42, g) * (0.62 + 0.38*spiralRaw)
```

- Total source emissivity now gets positive physical-field support, not just skin fraction support:

```text
pcdSourceField = max(pcdDensity, 0.11*radialGate)
               * (1 + radialGate*(0.48*spiral + 0.70*clump + 1.05*hotCrescent + 0.82*activity))

sourceScale = emissivityScale * pcdSourceField * positiveHeatingLift * conservationLift
```

- Skin remains positive-only emission:

```text
T_skin = T_obs * (1.58 + 2.35*activity + 0.78*filament + 0.44*gBoost + 0.58*hotCrescent)
```

No albedo, normal, roughness, specular, screen-space texture, bloom, tone mapping, or exposure fix was used.

## Default Source Preset Change

`physics-constrained-cinematic-disk-v1` defaults in `run_pipeline.sh` were made more structurally active:

```text
pcd-emissivity-scale = 1.22
pcd-structure-scale  = 1.45
pcd-spiral-amp       = 0.42
pcd-clump-contrast   = 0.52
pcd-hot-crescent     = 0.55
```

These are still bounded source-field parameters, not presentation parameters.

## Validation Commands

```bash
bash -n Blackhole/run_pipeline.sh
python3 -m py_compile scripts/validate_physics_constrained_cinematic_disk.py
git diff --check
xcodebuild -project Blackhole.xcodeproj -scheme Blackhole -configuration Release -derivedDataPath /private/tmp/ProjectGargantuaSourceRepairDerivedData build
/private/tmp/ProjectGargantuaSourceRepairDerivedData/Build/Products/Release/Blackhole --validate-packed-abi --print-packed-layout
BH_DERIVED_DATA_PATH=/private/tmp/ProjectGargantuaSourceRepairDerivedData bash Blackhole/run_pipeline.sh --source-model physics-constrained-cinematic-disk-v1 --quality preview --presentation scientific --look linear --width 160 --height 90 --output /private/tmp/bh_pcd_source_repair/default_scientific_linear.png --no-build
BH_DERIVED_DATA_PATH=/private/tmp/ProjectGargantuaSourceRepairDerivedData python3 scripts/validate_physics_constrained_cinematic_disk.py --width 160 --height 90 --out-dir /private/tmp/bh_pcd_source_repair_ab2 --no-build
```

## Output Paths

- Default scientific-linear preview: `/private/tmp/bh_pcd_source_repair/default_scientific_linear.png`
- A/B sheet: `/private/tmp/bh_pcd_source_repair_ab2/ab_sheet.png`
- A/B metrics: `/private/tmp/bh_pcd_source_repair_ab2/ab_metrics.json`
- A/B report: `/private/tmp/bh_pcd_source_repair_ab2/ab_report.md`
- Build log: `/private/tmp/bh_pcd_source_repair_xcodebuild.log`

## A/B Results

| Metric | Value | Gate |
|---|---:|---|
| no-structure vs high-structure activity RMSE | 0.1542 | pass |
| no-structure vs high-structure density RMSE | 0.0497 | pass |
| no-structure vs high-structure emissivity RMSE | 0.1578 | pass |
| no-structure vs high-structure final RGB RMSE | 0.0260 | pass |
| high_tau vs low_tau optical-depth RMSE | 0.1865 | pass |
| transfer-saturation mean difference | 0.0557 | pass |
| high-Doppler asymmetry ratio | 37.20 | pass |

Preset luma notes from `ab_metrics.json`:

| Preset | final mean luma | activity mean | emissivity mean | optical-depth mean | transfer saturation mean |
|---|---:|---:|---:|---:|---:|
| no_structure | 0.01649 | 0.02677 | 0.05741 | 0.05056 | 0.01978 |
| high_structure | 0.01131 | 0.04796 | 0.03077 | 0.05186 | 0.01986 |
| low_tau | 0.01321 | 0.05570 | 0.04039 | 0.03140 | 0.00000 |
| high_tau | 0.01321 | 0.05570 | 0.04039 | 0.03167 | 0.05568 |
| high_doppler | 0.03381 | 0.15596 | 0.16418 | 0.16045 | 0.02074 |

## Interpretation

The source model is now functionally active:

- density changes under high-structure controls;
- emissivity-pre-transfer changes strongly;
- optical-depth and transfer-saturation respond to opacity controls;
- high-Doppler preset produces strong g/beaming asymmetry;
- final scientific-linear PNG changes enough to pass the A/B gate.

The repair reflects at least these physical features in source/final diagnostics:

- radial brightness / density falloff;
- one-sided Doppler / g-factor asymmetry in the high-Doppler preset;
- nonuniform emissivity patches from disk-coordinate clumps;
- spiral/arc structure from logarithmic spiral support;
- optical-depth / transfer-saturation variation;
- inner hot crescent support.

## Remaining Limitations

- The model is still a physics-constrained surrogate, not real GRMHD.
- Profile 6 still shares ray/disk intersection and base blackbody transfer with the thin visible reference path. This is physically appropriate for the source backbone, but future work may need a cleaner code-level separation for maintainability.
- `high_structure` final mean luma is lower than `no_structure` in PNG output despite stronger source diagnostics and final RMSE. That suggests the scientific display/output PNG path still compresses or redistributes brightness. Do not solve this with bloom/tone mapping; the next pass should inspect raw radiance and exposure/display scaling separately.
- The A/B validation proves functionality, not final visual quality.

## Next Task

Run a fixed-exposure/raw-radiance comparison for `no_structure`, default, and `high_structure` to separate source radiance brightness from scientific-display PNG normalization. If raw radiance shows the same dimming, adjust the source energy budget. If raw radiance is healthy but PNG is dim, document and tune the scientific display scale without changing source morphology.
