# Accretion Disk Workflow V1

Date: 2026-05-02

Branch: `codex/integration/physics-camera-v1-legacy-recovery`

## Goal

Consolidate accretion-disk rendering into three primary workflows while keeping diagnostics, legacy reproduction paths, and experimental GRMHD branches clearly separated.

The source layer remains primary:

```text
source radiance -> relativistic transfer -> scientific / eye / cinema presentation
```

Eye/cinema modes interpret an already-built source. They must not create missing disk structure.

## Source-Model Registry

| Source model | Category | Purpose |
| --- | --- | --- |
| `canonical-visible-disk-v1` | reference | Scientific visible-disk baseline. Clean thin/intermediate body plus bounded positive hot-skin/corona source terms. |
| `cinematic-physical-disk-v1` | production | Physically constrained procedural cinematic disk for dataset-free exploration. Uses the same source-layer contract as canonical, with stronger disk-coordinate heating defaults. |
| `grmhd-surrogate-disk-v1` | production / experimental-surrogate | Synthetic GRMHD-like preview disk. It is not real GRMHD data and must be labeled as surrogate in reports. |
| `thin-disk-visible-reference` | reference | Clean analytic thin-disk reference with texture/GRMHD perturbations disabled. |
| `grmhd-hot-flow-diagnostic` | diagnostic | GRMHD-native optically thin hot-flow diagnostic. |
| `grmhd-temperature-flow-diagnostic` | diagnostic | GRMHD thermal visible volume RT diagnostic. |
| `thin-luminous-layer-candidate` | experimental | GRMHD thin photosphere/layer experiment. |
| `grmhd-plasma-fluctuation-candidate` | experimental | GRMHD hot-flow/plasma fluctuation candidate. |
| `grmhd-visible-disk-skin-candidate` | experimental | GRMHD skin-on-visible-reference candidate. |
| `flow`, `perlin`, `perlin-classic`, `perlin-ec7`, `noise` via `--disk-model` | legacy | Compatibility/reproduction selectors, not recommended final science workflows. |

## Workflow 1: `canonical-visible-disk-v1`

Purpose:

- Reference/scientific baseline.
- Stable thin/intermediate disk body.
- Bounded positive hot-skin branch.
- Weak corona branch.

Scientific assumptions:

- The body is an optically thick visible photosphere using the existing thin-disk ray/intersection path.
- Radial flux/temperature is controlled by `--teff-model`, `--teff-T0`, `--teff-r0`, `--teff-p`, `--fcol`, and relativistic transfer.
- Hot-skin activity is generated in disk coordinates and enters emissivity/temperature, not albedo, normal, roughness, or screen texture.

Diagnostics:

- `--realism-debug photosphere`
- `--realism-debug skin`
- `--realism-debug corona`
- `--realism-debug activity`
- `--realism-debug perturbation`
- `--realism-debug hdr`

Recommended preview:

```bash
./Blackhole/run_pipeline.sh \
  --source-model canonical-visible-disk-v1 \
  --presentation scientific \
  --look linear \
  --quality preview \
  --width 640 --height 360 \
  --output /private/tmp/canonical_visible_disk_v1.png
```

## Workflow 2: `cinematic-physical-disk-v1`

Purpose:

- Dataset-free production workflow for realistic/cinematic accretion-disk exploration.
- More visible disk-coordinate structure than canonical, but still physically constrained.

Included source elements:

- radial temperature gradient
- azimuthal turbulent contrast
- spiral / filament / clump-like heating through disk-coordinate stochastic modes
- Doppler/redshift compatibility through the same transfer path
- optical-depth-like body/skin/corona branch budgeting
- finite photospheric body support through the thin/intermediate source path
- nonuniform emissivity through positive hot-skin activity

Default source controls:

- thin disk source path
- `--realism-profile canonical-visible-disk-v1`
- stronger `--disk-turbulence`
- no Perlin/fBm/material texture
- no cloud opacity floor
- filmic presentation default, while scientific validation remains available by explicitly passing `--presentation scientific --look linear`

Scientific status:

- Physically constrained procedural source, not a solved fluid simulation.
- Acceptable for visual exploration only when accompanied by source diagnostics.

Recommended validation:

```bash
./Blackhole/run_pipeline.sh \
  --source-model cinematic-physical-disk-v1 \
  --presentation scientific \
  --look linear \
  --quality preview \
  --width 640 --height 360 \
  --output /private/tmp/cinematic_physical_disk_v1_scientific.png
```

## Workflow 3: `grmhd-surrogate-disk-v1`

Purpose:

- Synthetic GRMHD-like preview/experimentation workflow when real evolved GRMHD data is unavailable.
- Provides a deterministic, disk-coordinate surrogate for MRI-like turbulent heating structure.

Important limitation:

- This is not real GRMHD data.
- It must not be reported as a GRMHD simulation result.
- It is a surrogate source model for previewing morphology, search, and camera behavior.

Surrogate components:

- lognormal-like positive heating response from disk-coordinate spectral field
- MRI-like azimuthal turbulence through Kepler-sheared modes
- correlated radial/azimuthal structures in log-radius coordinates
- hot spots / arcs through positive packet and filament terms in the canonical heating field
- temperature fluctuations through hot-skin hardening
- velocity perturbation proxy through orbital boost / radial drift controls
- optional vertical/photosphere support through existing thin/intermediate disk geometry
- deterministic behavior controlled by source parameters such as `--disk-time`

Recommended validation:

```bash
./Blackhole/run_pipeline.sh \
  --source-model grmhd-surrogate-disk-v1 \
  --presentation scientific \
  --look linear \
  --quality preview \
  --width 640 --height 360 \
  --output /private/tmp/grmhd_surrogate_disk_v1_scientific.png
```

## Parameter Search

Script:

```bash
python3 scripts/search_disk_appearance.py \
  --source-model cinematic-physical-disk-v1 \
  --count 10 \
  --top 3 \
  --width 160 \
  --height 90 \
  --out-dir /private/tmp/bh_disk_appearance_search
```

Outputs:

- `metrics.json`
- `best_params.json`
- `top_candidates_contact.png`
- low-resolution candidate renders
- diagnostics for top candidates: photosphere, skin, corona, activity, perturbation, hdr

Metrics:

- luma entropy
- radial contrast
- azimuthal variance
- crescent asymmetry
- saturated pixel ratio
- black background preservation
- high-frequency texture energy
- ring sharpness proxy

Scoring:

- Physics score favors radial structure, azimuthal variance, crescent asymmetry, ring sharpness, and black-background preservation.
- Cinematic score favors entropy, readable high-frequency source structure, active-region brightness, crescent asymmetry, and low saturation.
- The score is a decision aid, not a replacement for visual/diagnostic review.

## M1 Pro Recommendations

Preview:

- `--quality preview`
- `--width 640 --height 360` for manual review
- `--width 160 --height 90` for search
- scientific validation first: `--presentation scientific --look linear`

Final review:

- `--quality hq`
- `--width 1536 --height 864` or similar
- render scientific, eye, and cinema from the same selected source parameters

## Validation Commands

```bash
bash -n Blackhole/run_pipeline.sh
python3 -m py_compile scripts/search_disk_appearance.py
python3 scripts/search_disk_appearance.py --count 10 --top 3 --width 160 --height 90 --out-dir /private/tmp/bh_disk_appearance_search --no-build
xcodebuild -project Blackhole.xcodeproj -scheme Blackhole -configuration Release -derivedDataPath /private/tmp/ProjectGargantuaDiskWorkflowDerivedData build
/private/tmp/ProjectGargantuaDiskWorkflowDerivedData/Build/Products/Release/Blackhole --validate-packed-abi --print-packed-layout
```

Executed validation:

- `bash -n Blackhole/run_pipeline.sh`: passed.
- `python3 -m py_compile scripts/search_disk_appearance.py`: passed.
- `python3 scripts/validate_cli_surface.py`: passed.
- `./Blackhole/run_pipeline.sh --help source-models`: passed and lists the three primary workflows plus diagnostics.
- `./Blackhole/run_pipeline.sh --source-model cinematic-physical-disk-v1 --validate-packed-abi`: parsed and executed ABI validation.
- `./Blackhole/run_pipeline.sh --source-model grmhd-surrogate-disk-v1 --validate-packed-abi`: parsed and executed ABI validation.
- Low-resolution search: passed with 10 candidates and top-3 diagnostics under `/private/tmp/bh_disk_appearance_search`.
- Xcode Release build: passed using `/private/tmp/ProjectGargantuaDiskWorkflowDerivedData`.
- Packed ABI validation: passed.

Search outputs:

- `/private/tmp/bh_disk_appearance_search/metrics.json`
- `/private/tmp/bh_disk_appearance_search/best_params.json`
- `/private/tmp/bh_disk_appearance_search/top_candidates_contact.png`
- `/private/tmp/bh_disk_appearance_search/canonical_compare.png`
- `/private/tmp/bh_disk_appearance_search/grmhd_surrogate_smoke.png`

Top low-resolution search candidates:

| Candidate | Score | Physics | Cinematic | Mean luma | Active mean | Entropy | Radial contrast | Azimuthal variance | HF energy | Saturation |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `cand_03` | 0.711791 | 0.632353 | 0.821490 | 0.017207 | 0.227303 | 0.788862 | 2.520577 | 0.119764 | 0.255677 | 0.000000 |
| `cand_06` | 0.711065 | 0.631125 | 0.821459 | 0.017665 | 0.232313 | 0.792213 | 2.443291 | 0.115129 | 0.258898 | 0.000000 |
| `cand_02` | 0.710802 | 0.630514 | 0.821676 | 0.018859 | 0.246909 | 0.804370 | 2.335451 | 0.112009 | 0.269335 | 0.000000 |

Reference comparison at 160x90:

| Render | Mean luma | Active mean | p95 luma | Active fraction |
| --- | ---: | ---: | ---: | ---: |
| `canonical_compare.png` | 0.018865 | 0.246535 | 0.169477 | 0.076458 |
| `cand_03.png` | 0.017207 | 0.227303 | 0.142576 | 0.075625 |
| `grmhd_surrogate_smoke.png` | 0.017719 | 0.233008 | 0.150703 | 0.075972 |

Interpretation:

- The search harness works and produces differentiated candidates plus diagnostics.
- `cand_03` won the combined score because it preserved black background, radial structure, and high-frequency source energy without saturation.
- At this resolution, the searched cinematic candidate is slightly dimmer than canonical. That is acceptable for search validation but should be reviewed visually before treating it as a final production preset.
- The surrogate smoke render is operational and must remain labeled synthetic.

## Remaining Limits Without Real GRMHD Data

- Turbulence is synthetic and source-layer constrained, not evolved fluid dynamics.
- The surrogate cannot validate angular momentum transport, magnetic stresses, or real plasma thermodynamics.
- A realistic evolved GRMHD dataset remains required for claims about actual accretion-flow morphology.
- The surrogate is useful for camera/interpreter testing and plausible visual exploration, not as a replacement for simulation truth.
