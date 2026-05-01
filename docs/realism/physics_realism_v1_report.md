# Physics Realism V1 Report

Branch: `codex/physics-realism-v1`

This report summarizes the physics-only realism branch after the diagnostic, thin-layer candidate, and radiative-transfer contrast work.

## 1. Branch Summary

### What this branch changed

- Added and documented the physics branch plan in `docs/realism/physics_realism_v1_plan.md`.
- Improved physics-owned diagnostics for already-computed transfer quantities:
  - optical depth aliases: `optical_depth`, `physics_optical_depth`, `optical_depth_wide`, `physics_optical_depth_wide`
  - physical hit-mask behavior for debug display paths
  - transfer saturation diagnostic: `transfer-saturation = 1 - exp(-tau)`
  - pre/post transfer aliases: `emissivity-pre-transfer` and `radiance-post-transfer`
- Added a small source-model candidate, `thin-luminous-layer-candidate`, that uses existing GRMHD visible thermal RT controls to test a thinner tau-surface/photosphere-like emitting layer.
- Added documentation:
  - `docs/realism/physics_diagnostics_notes.md`
  - `docs/realism/thin_luminous_layer_notes.md`
  - `docs/realism/radiative_transfer_contrast_notes.md`

### What was intentionally not changed

- No tone mapping, bloom, glare, lens flare, exposure, camera response, sensor response, color grading, or final display beautification was changed.
- No broad geodesic, metric, or transfer rewrite was attempted.
- No Metal buffer layout or packed ABI layout was changed.
- Existing presets and render paths were preserved.
- The thin luminous layer work is a candidate source-model default using existing controls, not a new shader architecture.

## 2. Physical Improvements

### Diagnostics added or improved

- Optical depth can now be requested with render-contract-friendly aliases such as `--disk-grmhd-debug optical_depth`.
- `transfer-saturation` exposes whether optical depth is driving transfer toward saturation using existing accumulated tau.
- `emissivity-pre-transfer` maps to the existing weighted thermal emissivity diagnostic, making the pre-transfer physical signal easier to compare.
- `radiance-post-transfer` maps to the existing thermal radiance contribution diagnostic, making post-transfer signal loss easier to inspect.
- `hit-mask` returns a physical hit/no-hit map in the linear debug path, including black for misses.

### Disk/emission improvements

- `thin-luminous-layer-candidate` provides a low-risk GRMHD visible thermal candidate that constrains emission to a thin tau-surface/photosphere-like layer using existing thin-photosphere and thermal-transfer controls.
- The candidate is intended for GRMHD volume inputs and preserves old source models.
- No imported GRMHD density, magnetic field, velocity, or metric data is modified by this candidate.

### Transfer/contrast improvements

- The branch does not tune final RGB contrast. It exposes physical transfer saturation so structure loss can be attributed to emissivity, opacity, source-function closure, or optical depth.
- The recommended comparison set is:
  - `emissivity-pre-transfer`
  - `radiance-post-transfer`
  - `optical_depth`
  - `transfer-saturation`
  - `source`
  - `thin-weight`
  - `emission-layer`

### Redshift/g-factor, hit, and source-location improvements

- Redshift/g-factor was already present through `g`, `beaming`, and `CollisionInfo.v_disk.x`; this branch documented that path but did not change the physics.
- Hit-mask inspection was improved in the debug display path.
- Source-location proxies were documented and remain available through `emission-radius`, `tau1-r`, `tau1-depth`, `path`, and related overloaded collision payload fields.

## 3. Render Contract Status

| Field | Status | Notes |
| --- | --- | --- |
| raw radiance | partial | Existing `raw-radiance`/`raw-log`, `inu`, `VolumeAccum.I`, `IVisNu`, and branch integrals are available. No dedicated raw-radiance buffer was added. |
| optical depth | available | `tau`, `optical_depth`, `tau-wide`, `optical_depth_wide`, `tau1-r`, and `tau1-depth` are inspectable for GRMHD/precision volume paths. Coverage outside volume paths remains more limited. |
| redshift/g-factor | available | `g`, `gfactor`, `redshift`, and `beaming` are available through existing debug modes; visible transport still uses g-factor physics. |
| hit mask | available | `hit-mask`/`hitmask`/`hit`/`hits` expose hit/no-hit diagnostics in the linear debug path. Rich hit-kind classification is not present. |
| emission radius/source proxy | partial | `emission-radius`, `tau1-r`, `tau1-depth`, `path`, and source-coordinate payloads exist, but fields remain mode-dependent and overloaded. |
| depth/distance proxy | partial | `path`, `ct`, and `tau1-depth` exist. There is no stable interpreter-facing depth buffer. |
| disk velocity | partial | `speed`, `gamma`, and existing `v_disk` payloads expose velocity-related proxies. A clean full velocity-vector contract is not available. |
| disk normal | missing | No stable exported disk-normal diagnostic or contract field was added. |
| temperature proxy | available | `teff`, `thetae`, `CollisionInfo.T`, and `VolumeAccum.temp4` provide temperature or temperature-proxy diagnostics, with source-mode-dependent meaning. |
| debug flags | partial | Existing `diskGrmhdDebugView`, `analysisMode`, invalid/sample views, and sentinel payload conventions remain. No unified debug-flags buffer was added. |

## 4. Validation

### Commands run

```bash
git status --short
bash -n Blackhole/run_pipeline.sh
./run_pipeline.sh --help | rg "thin-luminous-layer-candidate|transfer-saturation|emissivity-pre-transfer|radiance-post-transfer|optical_depth"
xcodebuild -project Blackhole.xcodeproj -scheme Blackhole -configuration Release -derivedDataPath /tmp/BlackholeDD_rebuild build
/tmp/BlackholeDD_rebuild/Build/Products/Release/Blackhole --validate-packed-abi --print-packed-layout --disk-mode grmhd --disk-grmhd-debug transfer-saturation
/tmp/BlackholeDD_rebuild/Build/Products/Release/Blackhole --validate-packed-abi --print-packed-layout --disk-mode grmhd --disk-grmhd-debug emissivity-pre-transfer
/tmp/BlackholeDD_rebuild/Build/Products/Release/Blackhole --validate-packed-abi --print-packed-layout --disk-mode grmhd --disk-grmhd-debug optical_depth
./run_pipeline.sh --source-model canonical-visible-disk-v1 --quality preview --width 8 --height 8 --preset balanced --output /private/tmp/bh_physics_branch_report_smoke.png --no-build
```

### What passed

- Worktree was clean before the report update.
- Shell syntax validation passed.
- Help output advertises the thin-layer candidate and new/clarified diagnostics.
- Release build passed.
- Packed ABI validation passed for `transfer-saturation`, `emissivity-pre-transfer`, and `optical_depth`; reported layout remained:
  - `PackedParams.layout size=616 stride=624 align=16`
  - `CollisionInfo.layout size=64 stride=64 align=16`
  - `CollisionLite32.layout size=32 stride=32 align=16`
  - `ComposeParams.layout size=304 stride=304 align=16`
- Baseline canonical visible disk smoke render succeeded and wrote its generated image outside the repository under `/private/tmp`.

### What failed

- No validation command failed during this stabilization pass.
- Xcode emitted existing simulator/runtime warnings, but the build completed with `BUILD SUCCEEDED`.

### What could not be validated

- A real GRMHD transfer-diagnostic image matrix was not rendered because no `vol0`/`vol1` GRMHD volume inputs were supplied in this task.
- The thin luminous layer candidate was only parser/build validated in prior work and documented here; it still needs a real GRMHD volume render to judge physical behavior.
- No interpreter/camera integration validation was run on this branch.

## 5. Remaining Risks

### Physical risks

- High optical depth may physically hide structure, or it may be too high because opacity/source-function parameters are not yet calibrated against the target regime.
- `j/alpha` source-function behavior can still flatten contrast if the smooth thermal/body branch dominates.
- The thin luminous layer candidate may be too narrow for coarse volume resolution or may underrepresent optically thin corona/hot-skin emission.
- Source-location and radiance payloads remain overloaded by mode, so downstream interpretation must check active mode and debug view.

### Numerical risks

- Very high opacity still relies on clamped `dTau` and exponential transmittance; saturation diagnostics expose this but do not change the math.
- Debug maps use display ramps/log ranges for inspection, so quantitative review should prefer raw buffers or documented scaling where available.
- The branch did not alter geodesic tolerances or integration stepping; any pre-existing numerical ray/path risks remain.

### Performance risks

- The new diagnostics reuse existing accumulated quantities and should not add meaningful GPU cost.
- Real GRMHD validation at production resolution can still be expensive; diagnostic matrices should start low resolution.
- No new CPU-GPU synchronization was added.

### Merge risks with interpreter branch

- Interpreter changes must not overwrite `--disk-grmhd-debug` names, source-model routing, or debug analysis-mode handling.
- Any interpreter-side final display changes must preserve physics debug output visibility and avoid reinterpreting debug ramps as beauty images.
- Integration should verify that camera/exposure paths do not hide `raw-radiance`, `optical_depth`, `g`, `hit-mask`, `emission-radius`, or `transfer-saturation` outputs.

## 6. Recommended Integration Notes

### What the camera/interpreter branch can consume

- `--disk-grmhd-debug optical_depth`
- `--disk-grmhd-debug optical_depth_wide`
- `--disk-grmhd-debug transfer-saturation`
- `--disk-grmhd-debug emissivity-pre-transfer`
- `--disk-grmhd-debug radiance-post-transfer`
- `--disk-grmhd-debug g`
- `--disk-grmhd-debug beaming`
- `--disk-grmhd-debug hit-mask`
- `--disk-grmhd-debug emission-radius`
- `--source-model thin-luminous-layer-candidate` for GRMHD volume tests

### What should be checked during later integration

- Render the same GRMHD volume with pre-transfer emissivity, post-transfer radiance, optical depth, transfer saturation, source function, thin weight, and emission layer.
- Confirm debug outputs bypass or survive camera/interpreter post-processing in a clearly labeled way.
- Confirm any final display improvement does not change the underlying physical radiance, opacity, g-factor, or source-location values.
- Verify that source-model defaults still route to the intended physics controls after interpreter branch merges.

### What should not be overwritten by interpreter changes

- Physics-owned source parameters: density/emission/absorption scales, photosphere/layer weights, thermal-transfer mode, emissivity and absorptivity logic.
- Debug aliases and their mapping to existing physical channels.
- `transfer-saturation` as a tau-derived diagnostic, not a display contrast operator.
- Existing separation between physical signal production and final visual interpretation.
