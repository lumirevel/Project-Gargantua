# First Merge Verification V1

Date: 2026-05-02

Branch under test: `codex/integration/physics-camera-v1-legacy-recovery`

Purpose: verify whether `codex/physics-realism-v1` is included in the integration branch before fixing current legacy/perlin issues.

This pass is read-only for source code. No code changes or commits were made by this verification. This report file is the only intended repository change from the pass.

## 1. Branch State

Current branch:

```text
codex/integration/physics-camera-v1-legacy-recovery
```

Current HEAD:

```text
6a5860e merge physics and camera realism branches
```

Recent relevant history:

```text
6a5860e merge physics and camera realism branches
3ab3413 record physics merge validation
1779917 Merge remote-tracking branch 'origin/codex/physics-realism-v1' into codex/integration/physics-camera-v1
49a3cb6 document physics camera integration branch
4556f88 origin/codex/physics-realism-v1
180435d origin/codex/interpreter-camera-v1
```

Worktree note:

- Existing untracked files were present before this report:
  - `.claude/`
  - `hello.png.exposure_debug.json`
  - `hello_canon.png.exposure_debug.json`
  - `hello_perlin.png.exposure_debug.json`
  - `hello_perlin_classic.png.exposure_debug.json`
- These look unrelated to first-merge verification and should not be committed without review.

## 2. Merge Inclusion

Graph checks:

```bash
git merge-base --is-ancestor origin/codex/physics-realism-v1 HEAD
git merge-base --is-ancestor origin/codex/interpreter-camera-v1 HEAD
```

Results:

- `origin/codex/physics-realism-v1` is an ancestor of `HEAD`: yes.
- `origin/codex/interpreter-camera-v1` is an ancestor of `HEAD`: yes.

Conclusion:

- Physics merge is graph-successful.
- Camera merge is also graph-successful.

## 3. Physics File Preservation

Requested physics-core files:

| File | Present in physics branch | Present in HEAD | Difference from physics branch | Assessment |
| --- | --- | --- | --- | --- |
| `Blackhole/Metal/VolumeTransport/grmhd.metal` | yes | yes | identical | preserved |
| `Blackhole/Metal/volume_rt.metal` | yes | yes | identical | preserved |
| `Blackhole/Metal/disk_models.metal` | yes | yes | identical | preserved |
| `Blackhole/Metal/Compose/helpers.metalh` | yes | yes | changed after physics | preserved but camera/interpreter compose changes are layered on top |
| `Blackhole/Sources/Core/ABI/PackedParams.swift` | yes | yes | changed after physics | preserved with later ABI extension |
| `Blackhole/Sources/Params/ParamsBuilder.swift` | yes | yes | changed after physics | preserved with later camera/interpreter config additions |
| `Blackhole/Sources/Params/ParamsBuilderPolicy.swift` | yes | yes | identical | preserved |
| `Blackhole/Sources/Params/ParamsBuilderPacking.swift` | yes | yes | identical | preserved |
| `Blackhole/run_pipeline.sh` | yes | yes | changed after physics | preserved with CLI union resolution |
| `Blackhole/scripts/run_grmhd_diagnostic_matrix.py` | yes | yes | identical | preserved |
| `Blackhole/scripts/build_grmhd_volumes.py` | yes | yes | identical | preserved |
| `docs/realism/physics_realism_v1_report.md` | yes | yes | identical | preserved |

Conclusion:

- Physics merge is file-successful for the requested core physics files.
- The files changed after physics are expected shared/integration or interpreter-facing files. No evidence was found that physics-owned GRMHD transport/source files were overwritten by camera work.

## 4. Physics Feature Keyword Preservation

Keyword checks were run with `rg` across `Blackhole`, `docs`, and `scripts`.

| Keyword | Current HEAD status | Main locations |
| --- | --- | --- |
| `thin-luminous-layer-candidate` | present | `Blackhole/run_pipeline.sh`, `docs/realism/physics_realism_v1_report.md`, `docs/realism/thin_luminous_layer_notes.md` |
| `transfer-saturation` | present | `Blackhole/run_pipeline.sh`, `Blackhole/Sources/Params/ParamsBuilderPolicy.swift`, `docs/realism/radiative_transfer_contrast_notes.md` |
| `emissivity-pre-transfer` | present | `Blackhole/run_pipeline.sh`, `Blackhole/Sources/Params/ParamsBuilderPolicy.swift`, `docs/realism/radiative_transfer_contrast_notes.md` |
| `radiance-post-transfer` | present | `Blackhole/run_pipeline.sh`, `Blackhole/Sources/Params/ParamsBuilderPolicy.swift`, `docs/realism/radiative_transfer_contrast_notes.md` |
| `optical_depth` | present | `Blackhole/run_pipeline.sh`, `docs/realism/physics_realism_v1_report.md`, integration reports |
| `optical_depth_wide` | present | `Blackhole/run_pipeline.sh`, `Blackhole/Sources/Params/ParamsBuilderPolicy.swift`, `docs/realism/physics_diagnostics_notes.md` |
| `grmhd-plasma-fluctuation-candidate` | present | `Blackhole/run_pipeline.sh`, `docs/realism/plasma_fluctuation_notes.md` |
| `grmhd-visible-disk-skin-candidate` | present | `Blackhole/run_pipeline.sh`, `docs/realism/plasma_fluctuation_notes.md` |
| `grmhd-temperature-flow-diagnostic` | present | `Blackhole/run_pipeline.sh`, `docs/source_models.md`, `docs/scientific_rendering_policy.md` |

Conclusion:

- Physics feature names and debug aliases are still present.
- The public source registry currently includes the GRMHD candidate/diagnostic models, so the physics branch's source-model exposure was not lost.

## 5. Minimal Behavior Validation

### Shell syntax and help exposure

Commands:

```bash
bash -n Blackhole/run_pipeline.sh
./Blackhole/run_pipeline.sh --help | rg "thin-luminous-layer|transfer-saturation|emissivity-pre-transfer|optical_depth"
```

Result:

- Passed.
- Help output exposes `thin-luminous-layer-candidate`, `transfer-saturation`, `emissivity-pre-transfer`, and `optical_depth`.

### Xcode build

Command:

```bash
xcodebuild -project Blackhole.xcodeproj -scheme Blackhole -configuration Release -derivedDataPath /private/tmp/ProjectGargantuaFirstMergeVerifyDerivedData build
```

Result:

- Passed.
- Existing local xrOS simulator duplicate runtime warnings appeared. They did not block the build.

### Packed ABI validation and parse validation

Commands:

```bash
/private/tmp/ProjectGargantuaFirstMergeVerifyDerivedData/Build/Products/Release/Blackhole --validate-packed-abi --print-packed-layout
/private/tmp/ProjectGargantuaFirstMergeVerifyDerivedData/Build/Products/Release/Blackhole --validate-packed-abi --print-packed-layout --disk-mode grmhd --disk-grmhd-debug optical_depth
/private/tmp/ProjectGargantuaFirstMergeVerifyDerivedData/Build/Products/Release/Blackhole --validate-packed-abi --print-packed-layout --disk-mode grmhd --disk-grmhd-debug transfer-saturation
/private/tmp/ProjectGargantuaFirstMergeVerifyDerivedData/Build/Products/Release/Blackhole --validate-packed-abi --print-packed-layout --disk-mode grmhd --disk-grmhd-debug emissivity-pre-transfer
```

Result:

- Passed.

Observed layout:

```text
PackedParams.layout size=616 stride=624 align=16
CollisionInfo.layout size=64 stride=64 align=16
CollisionLite32.layout size=32 stride=32 align=16
ComposeParams.layout size=320 stride=320 align=16
ComposeSolveParams.layout size=32 stride=32 align=4
ComposeSolveResult.layout size=32 stride=32 align=4
PackedParams.offset grmhdBranchIsolationMode=596
PackedParams.offset grmhdSmoothWeightMode=612
```

Conclusion:

- Physics merge is behavior-successful at syntax, CLI exposure, build, ABI, and debug-option parse levels.
- This pass did not run actual GRMHD debug image generation, so image-level behavior remains unverified.

## 6. Overall First-Merge Judgment

### Graph-level judgment

Successful.

`origin/codex/physics-realism-v1` is an ancestor of the current HEAD.

### File-level judgment

Successful with expected shared-file layering.

Physics-owned shader/source files such as `grmhd.metal`, `volume_rt.metal`, `disk_models.metal`, `ParamsBuilderPolicy.swift`, `ParamsBuilderPacking.swift`, GRMHD scripts, and the physics report are preserved.

Shared files modified after the physics merge are mainly compose/interpreter/ABI/CLI surfaces. These need later review, but they do not show obvious physics loss.

### Behavior-level judgment

Mostly successful, but not complete.

The branch builds, ABI validation passes, and physics debug aliases parse. Actual GRMHD diagnostic render output has not been proven in this verification pass.

## 7. Incomplete Or Suspicious Areas

1. Image-level GRMHD diagnostics remain unverified.
   - Need actual bounded-time renders for `optical_depth`, `transfer-saturation`, and `emissivity-pre-transfer`.

2. `Blackhole/Metal/Compose/helpers.metalh` changed substantially after physics.
   - This is expected from interpreter/camera work, but it is the most important shared file to inspect if physics debug output is visually wrong.

3. `Blackhole/run_pipeline.sh` contains both the consolidated source registry and legacy/perlin routing.
   - The current help still exposes legacy disk model/source options such as `perlin`, `perlin-classic`, `perlin-ec7`, and `disk-precision-texture`.
   - This may be intentional for reproduction, but it is directly relevant to the legacy/perlin issue.

4. Untracked exposure debug JSON files are present at repo root.
   - These are likely generated outputs and should not be committed.

## 8. Next Fix Targets

Before fixing behavior, verify actual render output with a small bounded matrix:

```bash
--disk-mode grmhd --disk-grmhd-debug optical_depth
--disk-mode grmhd --disk-grmhd-debug transfer-saturation
--disk-mode grmhd --disk-grmhd-debug emissivity-pre-transfer
```

If image output is incorrect, inspect in this order:

1. `Blackhole/run_pipeline.sh`
   - source-model registry
   - science-regime mapping
   - legacy/perlin exposure
   - debug alias canonicalization

2. `Blackhole/Metal/Compose/helpers.metalh`
   - final diagnostic interpretation
   - debug output mapping
   - possible presentation contamination of physics diagnostics

3. `Blackhole/Metal/spectrum_visible.metal`
   - legacy/perlin synthetic noise paths
   - `comp_synthetic_noise`
   - debug/source interpretation of `rec.noise`

4. `Blackhole/Metal/VolumeTransport/grmhd.metal`
   - GRMHD texture-strength usage
   - comments around non-image-space texture
   - `diskPrecisionTexture` influence in GRMHD path

5. `Blackhole/Metal/VolumeTransport/legacy.metal`
   - older cloud/noise transport
   - direct legacy/perlin visual character

6. `Blackhole/Metal/disk_models.metal`
   - MRI-motivated turbulent heating field intended to replace Perlin/fBM texture

## 9. Legacy/Perlin Related File Candidates

Most directly related:

- `Blackhole/run_pipeline.sh`
- `Blackhole/Metal/spectrum_visible.metal`
- `Blackhole/Metal/VolumeTransport/legacy.metal`
- `Blackhole/Metal/VolumeTransport/grmhd.metal`
- `Blackhole/Metal/disk_models.metal`
- `Blackhole/Metal/gr_math.metal`
- `docs/source_models.md`
- `docs/scientific_rendering_policy.md`
- `docs/presentation_modes.md`

Reasoning:

- `run_pipeline.sh` exposes and routes `perlin`, `perlin-classic`, `perlin-ec7`, `disk-precision-texture`, and legacy source families.
- `spectrum_visible.metal` contains `comp_synthetic_noise` and perlin soft/cloud interpretation paths.
- `legacy.metal` contains older volume/cloud noise logic.
- `grmhd.metal` still uses `diskPrecisionTexture` as a state/flow texture-strength control in GRMHD paths.
- `disk_models.metal` contains the physically preferred MRI-inspired heating field and is the likely replacement path for decorative procedural texture.

## 10. Verification Result

The first physics merge is sufficiently successful to proceed to targeted bug fixing.

Do not assume the final visual/diagnostic output is correct yet. The next step should be bounded render-level verification, not another graph/file merge investigation.
