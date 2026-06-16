# Phase 0 To Phase 6 Execution State

Date: 2026-06-15

## Decision

Run Phase 0-6 cleanup and validation before promoting the GUI.

The GUI can exist as a thin prototype, but it must not become the main interface
until the renderer has contract-aware phase boundaries. Otherwise the GUI would
only move a confusing CLI into a confusing window.

## Phase 0: Baseline And Governance

Purpose:

- freeze the authority model
- document current phase boundaries
- separate unrelated dirty work
- add fast readiness checks
- keep generated images and local data out of commits

Current state:

- AI role protocol exists in `06_ai_role_protocol.md`.
- Physics, observer, render mode, reference validation, architecture, and
  implementation roadmap docs exist.
- `validate_realism_contract_docs.py` checks the core contract document surface.
- `validate_phase_readiness.py` checks the Phase 0-6 and GUI readiness surface.
- `validate_phase_completion_audit.py` records requirement-by-requirement
  completion evidence and intentionally fails while full-scope gaps remain.
- `validate_source_model_registry.py` checks Phase 4 registry drift across docs,
  help, and CLI validation.
- Existing worktree includes unrelated source changes and generated/local files;
  they must not be bundled into a single broad merge.

Phase 0 exit criteria:

- required contract docs pass validation
- phase readiness script passes
- `git diff --check` passes
- GUI work is clearly marked prototype/post-Phase-6
- next implementation tickets are explicit

Completion audit:

```bash
python3 scripts/validate_phase_completion_audit.py
```

This audit is expected to fail until the full objective is actually complete.
It currently marks Phase 0 governance and Phase 4 source registry as complete,
while tracking the remaining Phase 1/2/3/5/6/GUI gaps.

## Phase 1: Render Mode Separation

Goal:

- keep `scientific`, `human-eye`, `camera-raw`, `camera-rendered`,
  `cinematic`, and `legacy` conceptually separate
- expose missing modes honestly rather than relabeling one mode as another

Current state:

- CLI has `scientific`, `eye`, `camera-raw`, `camera-rendered`, and `cinema`.
- `camera-raw` is a first-class presentation name routed to an identity linear
  audit path for the display preview. It can emit a float4 linear32
  radiance/depth sidecar through `--hdr-intermediate --hdr-out` and an ideal
  pre-demosaic RGGB float32 CFA buffer through `--camera-raw-out`. The same
  converter can emit a documented reference `bayer-rggb-u16` sensor/ADC RAW
  sidecar with QE, photon/read noise, ISO gain, black/white levels, and 16-bit
  ADC quantization.
- `camera-rendered` is a first-class presentation name routed to the rendered
  camera interpretation path. It is distinct from `cinema`, which remains the
  L6 cinematic grade.
- GUI labels the neutral camera output as scientific RAW / linear audit,
  while the validator owns the reference sensor/ADC sidecar proof.
- `validate_render_mode_contract.py` now checks the first-class CLI names while
  preserving the calibrated sensor-physics gap.

Next tickets:

- RM-1: add named camera calibration profiles and proprietary-container export
  only after the reference sensor/ADC contract remains stable.
- RM-2: add mode matrix validation for same-radiance routes.
- RM-3: audit that cinematic output does not alter scientific output.

## Phase 2: Geodesic Correctness

Goal:

- prove ray paths before source/camera improvements are trusted

Current state:

- geodesic implementation exists in Metal.
- `validate_geodesic_scalar_baseline.py` now wraps the existing one-ray
  comparison tool and writes scalar evidence to
  `/private/tmp/bh_geodesic_scalar_baseline/geodesic_scalar_baseline.json`.
- Current hard smoke gates cover finite Kerr states, bounded null residual,
  positive radius, and `Lz` conservation for stable off-axis probes.
- The same validator now hard-gates the analytic Schwarzschild limit of the
  Kerr metric: Kerr `a = 0` must match the Schwarzschild BL covariant and
  inverse metric over a small `r/theta` grid.
- It also hard-gates Carter `Q` drift for stable non-stress Kerr probes,
  including the high-spin probe.
- It now hard-gates calibrated Schwarzschild-vs-Kerr `a = 0` Hamiltonian
  trajectory agreement from the same BL canonical state.
- It now hard-gates the Schwarzschild equatorial photon-sphere orbit
  (`r = 3M`, `L/E = 3*sqrt(3)`) on the Kerr `a = 0` Hamiltonian path.
- It now hard-gates a calibrated 3x3 image-plane near-critical grid around the
  centerline critical stencil with a smaller integration step.
- `--fail-on-contract-gaps` now passes for this Phase 2 validator; broader
  spin/inclination/field-of-view sweeps are future robustness work rather than
  the current completion blocker.

Next tickets:

- GEO-1: tighten metric signature, coordinate conventions, and thresholds.
- GEO-2: extend the calibrated critical grid across spin, inclination, and
  field-of-view for robustness.
- GEO-3: extend the calibrated Schwarzschild/Kerr trajectory fixture toward
  additional near-critical rays.

## Phase 3: Redshift / Doppler / Invariant Intensity

Goal:

- ensure brightness and color changes come from relativistic transfer

Current state:

- contract requires `g = nu_obs / nu_emit` and invariant `I_nu / nu^3`.
- existing code has redshift/g-factor plumbing and debug views.
- `validate_transfer_scalar_baseline.py` now validates static `g ~= 1`,
  Doppler ordering, `g^3` intensity transport, and implementation-surface
  evidence for the current Metal/Swift paths.
- `validate_transfer_gfactor_maps.py` now renders actual `--realism-debug g`
  and `--realism-debug beaming` maps for low-Doppler, controlled baseline, and
  high-Doppler cases, then gates finite maps, active diagnostic pixels, changed
  maps, stronger high-Doppler asymmetry, and high-vs-low Doppler separation.
- `static-transfer-reference-v1` is now a diagnostic source model that uses a
  Schwarzschild thin-disk scene with orbital, radial, and turbulent source
  motion disabled.
- `validate_transfer_static_renderer_fixture.py` renders the static-transfer
  source and an orbiting control, then gates finite g/beaming maps, active
  beaming diagnostic pixels, and measurable beaming/final-radiance response
  when orbital source motion is re-enabled. The current g PNG ramp is finite
  but too dark for this geometry to be the numeric gate.
- `validate_transfer_raw_g_debug.py` renders `--realism-debug raw-g` into a
  float HDR32 intermediate and reads raw renderer g-factor values directly,
  avoiding 8-bit PNG ramp ambiguity.
- `validate_transfer_same_tetrad_renderer_fixture.py` renders
  `--realism-debug same-tetrad-g` into a float HDR32 intermediate and gates the
  isolated local reference case `u_emit == u_obs`, where
  `(k_mu u_obs^mu) / (k_mu u_emit^mu) == 1`.

Next tickets:

- RT-1: extend rendered g-factor map checks beyond the current low/baseline/high
  Doppler source-model fixture.
- RT-2: audit for arbitrary scientific-mode brightness multipliers.

## Phase 4: Source Model Registry

Goal:

- make source models explicit, documented, and testable

Current state:

- CLI source-model registry exists.
- legacy disk models exist for reproduction.
- surrogate models need clear labels in GUI and reports.
- `docs/source_models.md` now distinguishes recommended, production-candidate,
  surrogate, diagnostic, and legacy status classes.
- `docs/source_models.md` now includes a Source Model Contract Matrix covering
  assumptions, inputs, outputs, known limitations, allowed render modes,
  validation scenes, and forbidden hacks for every public/candidate source.
- `validate_source_model_registry.py` verifies the current source-model surface
  and enforces the contract matrix template.

Next tickets:

- SRC-1: split long-form source docs into per-source files once the registry
  surface stabilizes.
- SRC-2: keep GUI source status labels synchronized with the registry matrix.
- SRC-3: keep legacy and surrogate models out of recommended science defaults.

## Phase 5: Observer / Camera Interpreter

Goal:

- keep human-eye, camera RAW-like, and rendered-camera outputs downstream of
  physical radiance

Current state:

- camera/interpreter CLI options exist.
- interpreter diagnostics exist, but not all mode outputs are first-class.
- `validate_observer_cinematic_contract.py` checks the RAW-like identity audit
  command surface and verifies that analysis/debug modes zero camera
  presentation effects in the Swift parameter policy.
- `validate_camera_raw_sidecar.py` renders `camera-raw` with camera effects
  disabled and verifies that the linear32 radiance/depth sidecar, metadata,
  display PNG, and ideal pre-demosaic RGGB float32 CFA sensor RAW buffer are
  written consistently. It also converts the same linear32 buffer into a
  reference RGGB u16 sensor/ADC RAW sidecar with QE, photon/read noise, ISO
  gain, black/white levels, and 16-bit ADC quantization.
- `validate_scientific_raw_purity.py` statically audits the Swift parser,
  compose policy, Metal compose gates, GUI command generation, and GUI matrix
  so scientific and `camera-raw` routes keep camera profile transforms,
  PSF/noise/flare/DOF/background, dithering, and filmic look out of the
  RAW-like audit path.

Next tickets:

- OBS-1: add named camera calibration profiles only after the reference
  sensor/ADC contract remains stable.
- OBS-2: decide whether the GUI should expose f32 CFA vs u16 sensor/ADC as a
  visible user choice.
- OBS-3: add thresholded pixel validation for interpreter-stage diagnostics.

## Phase 6: Cinematic Layer

Goal:

- allow bloom, flare, film look, and grading only as final presentation

Current state:

- cinema presentation and camera flare/DOF controls exist.
- phase gate requires proof that scientific and RAW-like diagnostics remain
  unchanged by cinematic effects.
- `validate_observer_cinematic_contract.py` records explicit cinematic-on and
  cinematic-off command surfaces, but does not yet prove pixel-level
  invariance.
- `validate_cinematic_pixel_invariance.py` now feeds a synthetic float4
  radiance/depth buffer through the real compose path and checks pixel-level
  presentation isolation for scientific audit, `camera-raw`, `camera-rendered`,
  and cinema outputs.
- `validate_blackhole_presentation_invariance.py` repeats the same pixel-level
  presentation isolation check on a low-resolution canonical black-hole source
  render.
- `validate_presentation_source_matrix.py` extends that source-render check
  across the recommended/candidate thin-disk source matrix:
  `canonical-visible-disk-v1`, `thin-disk-visible-reference`,
  `cinematic-physical-disk-v1`, and
  `physics-constrained-cinematic-disk-v1`.
- `validate_grmhd_presentation_fixture.py --suite --require-data` adds a
  data-backed GRMHD presentation isolation suite. On this machine it covers the
  local SANE/iharm-style snapshot at
  `/private/tmp/bh_real_grmhd_sequence/SANE_a0_torus.out0.05010.h5` and the
  converted FM/sample HDF5 fixture at
  `/private/tmp/bh-march-grmhd-repro/cache/sample.h5` with
  `grmhd-temperature-flow-diagnostic`.
- `validate_run_pipeline_look_policy.py` checks the CLI policy that
  `camera-raw`/scientific audit routes default to `linear` even when a source
  model has a filmic default look, and that `camera-raw` rejects non-linear
  user `--look` values.
- `validate_scientific_raw_purity.py` adds a fast static guard for scientific
  and RAW-like purity before the heavier pixel-level validators run.

Next tickets:

- CIN-1: add named paper-reference GRMHD calibration cases when a stable
  benchmark corpus is selected.
- CIN-2: render bloom/glare-only diagnostics where available.
- CIN-3: keep comparing no-effect vs cinematic output while holding source
  constant as new presentation effects are added.

## GUI Position

The GUI comes after Phase 0-6 readiness because it should select valid concepts,
not expose every CLI flag.

Current prototype:

```bash
tools/GargantuaLauncher/run_gui.sh
```

Prototype status:

- primary Xcode app target exists as `GargantuaLauncher`
- acceptable as a thin command generator
- source models and camera intents are loaded from
  `docs/realism/gui_option_manifest_v1.json`
- the manifest is bundled into the app target as a resource
- data-backed diagnostic sources can declare `requiresDiskHDF5` and
  `defaultDiskHDF5`; the launcher exposes a source-data field and includes
  `--disk-hdf5` in generated commands
- `validate_gui_primary_target.py` verifies the app target, bundled manifest,
  and that renderer/Metal physics files are not compiled into the GUI target
- `validate_gui_option_manifest.py` checks manifest/docs/CLI/launcher alignment
- `validate_gui_command_matrix.py` verifies that the GRMHD diagnostic source
  includes `--disk-hdf5` across eye, RAW-like, rendered, and cinematic intents
- must remain thin and contract-aware
- must not invent missing renderer modes

Promotion requirements:

- Phase 1 mode names are stable
- Phase 4 source registry is stable
- Phase 5 camera RAW/rendered split is explicit
- Phase 6 cinematic controls have off-switch validation
- GUI command generation has tests and a manifest-backed option model
