# Contract Implementation Roadmap

This roadmap turns the authority model and contracts into implementation order.
It is intentionally conservative: every phase must preserve the separation
between physical reality, observer interpretation, and cinematic presentation.

## Phase 0: Baseline And Governance

Goal: prevent broad mixed changes before the renderer boundaries are ready.

Exit criteria:

- required contract docs are present
- readiness validation passes
- dirty generated outputs are not part of the merge
- GUI work is marked as prototype until Phase 1-6 names and contracts stabilize
- next tickets are explicit

First tickets:

| Ticket | Owner | Scope | Validation |
| --- | --- | --- | --- |
| PH0-1 | Science Architect | Define Phase 0-6 exit criteria and GUI ordering. | `13_phase0_to_phase6_execution_state.md`. |
| PH0-2 | Implementation Agent | Add fast readiness validation for contracts and surfaces. | `scripts/validate_phase_readiness.py`. |
| PH0-3 | Verification Agent | Audit current dirty worktree for unrelated merge risk. | Status/diff report. |

## Phase 1: Render Mode Separation

Goal: make the output modes explicit before adding more realism.

Required modes:

- `scientific`
- `human-eye` / `eye`
- `camera-raw`
- `camera-rendered`
- `cinematic`
- `legacy`

Exit criteria:

- the same physical radiance can be routed through the available modes
- missing modes are reported as missing, not faked by relabeling another mode
- scientific output can disable visual improvements
- legacy output is clearly labeled reproduction

First tickets:

| Ticket | Owner | Scope | Validation |
| --- | --- | --- | --- |
| RM-1 | Science Architect | Define exact mode semantics and allowed transforms. | Contract review only. |
| RM-2 | Implementation Agent | Add or document `camera-raw` vs `camera-rendered` routing without changing physics. | Mode matrix and no physics diff. |
| RM-3 | Verification Agent | Audit that cinematic effects do not change scientific/RAW-like outputs. | Diff audit plus comparison sheet. |

## Phase 2: Geodesic Correctness

Goal: prove the ray paths before trusting source or camera output.

Required checks:

- null condition `k_mu k^mu = 0`
- Schwarzschild limit
- Kerr `a = 0` agrees with Schwarzschild
- conserved-quantity drift
- horizon crossing behavior
- photon-sphere / critical-curve stability
- adaptive step or error estimate behavior where applicable

First tickets:

| Ticket | Owner | Scope | Validation |
| --- | --- | --- | --- |
| GEO-1 | Science Architect | Define metric signature, coordinates, units, observer tetrad, and invariant thresholds. | `07_physics_contract.md` update. |
| GEO-2 | Implementation Agent | Add low-resolution geodesic invariant diagnostics without presentation changes. | Scalar report under `/private/tmp`. |
| GEO-3 | Verification Agent | Compare Schwarzschild and Kerr `a = 0` routes. | PASS / FAIL / PARTIAL report. |

Current baseline command:

```bash
python3 scripts/validate_geodesic_scalar_baseline.py
```

This writes `/private/tmp/bh_geodesic_scalar_baseline/geodesic_scalar_baseline.json`.
The hard gate covers finite Kerr states, bounded null residual, positive
radius, conserved `Lz` for stable off-axis probes, Kerr `a = 0` metric identity
against the Schwarzschild BL covariant/inverse metric, and Carter `Q` drift for
stable non-stress Kerr probes. It also includes a calibrated
Schwarzschild-vs-Kerr `a = 0` Hamiltonian trajectory agreement gate from the
same BL canonical state, a Schwarzschild equatorial photon-sphere orbit gate at
`r = 3M` with `L/E = 3*sqrt(3)`, and a calibrated 3x3 image-plane
near-critical grid using a smaller integration step. The validator supports
`--fail-on-contract-gaps`; that mode must pass before Phase 2 is considered
complete.

## Phase 3: Redshift, Doppler, And Invariant Intensity

Goal: make brightness and color changes come from relativistic transfer, not
hidden visual multipliers.

Required checks:

- static emitter/static observer gives `g ~= 1` for the stated geometry
- approaching side is brighter for physical velocity reasons
- receding side is dimmer for physical velocity reasons
- `I_nu / nu^3` is preserved by the transfer approximation
- frequency shift reaches the spectral/color layer

First tickets:

| Ticket | Owner | Scope | Validation |
| --- | --- | --- | --- |
| RT-1 | Science Architect | Define redshift and invariant-intensity equations for the next implementation pass. | Equation and tolerance contract. |
| RT-2 | Implementation Agent | Expose `redshift_g` and invariant-intensity diagnostics if missing. | Diagnostic render plus scalar summary. |
| RT-3 | Verification Agent | Audit for arbitrary scientific brightness multipliers. | Diff audit and grep-backed report. |

Current baseline command:

```bash
python3 scripts/validate_transfer_scalar_baseline.py
python3 scripts/validate_transfer_gfactor_maps.py
python3 scripts/validate_transfer_static_renderer_fixture.py
python3 scripts/validate_transfer_raw_g_debug.py
python3 scripts/validate_transfer_same_tetrad_renderer_fixture.py
```

The scalar baseline writes `/private/tmp/bh_transfer_scalar_baseline.json`. It
validates the static `g ~= 1` reference, Doppler ordering, `g^3` intensity
transport, and implementation-surface evidence in Metal/Swift.

The renderer map baseline writes
`/private/tmp/bh_transfer_gfactor_maps/gfactor_map_metrics.json` and renders
actual `--realism-debug g` and `--realism-debug beaming` outputs for a
low-Doppler case, a controlled baseline, and a high-Doppler case. It gates
finite maps, active diagnostic pixels, changed maps, stronger Doppler
asymmetry, and high-vs-low Doppler separation. It is still a narrow regression
fixture, not the final true static-emitter/static-observer renderer source.

The static-transfer renderer fixture writes
`/private/tmp/bh_transfer_static_renderer_fixture/static_transfer_fixture_metrics.json`
and renders `static-transfer-reference-v1`, a Schwarzschild thin-disk diagnostic
source with orbital, radial, and turbulent source motion disabled. It compares
that no-flow render against an orbiting control using the same source model and
gates finite g/beaming maps, active beaming diagnostics, and measurable
beaming/final-radiance response when orbital source motion is re-enabled. The
current g PNG ramp is finite but too dark in this geometry to be the numeric
gate. The fixture also does not require lower left/right asymmetry in the
no-flow image, because Schwarzschild gravitational redshift, lensing, and
projection geometry remain active. This is stronger than the previous
low-Doppler approximation, but it is not the final same-tetrad `g ~= 1`
renderer proof.

The raw g diagnostic writes
`/private/tmp/bh_transfer_raw_g_debug/raw_g_debug_metrics.json` and reads
`--realism-debug raw-g` from a float HDR32 intermediate. It gates finite raw g
values, monochrome float output, plausible static range, and measurable raw-g
change when orbital source motion is re-enabled.

The same-tetrad renderer fixture writes
`/private/tmp/bh_transfer_same_tetrad_renderer_fixture/same_tetrad_renderer_fixture_metrics.json`
and reads `--realism-debug same-tetrad-g` from a float HDR32 intermediate. It
gates the isolated local reference case `u_emit == u_obs`, where
`(k_mu u_obs^mu) / (k_mu u_emit^mu) == 1`, without changing physical scene
radiance or presentation output.

## Phase 4: Source Model Registry

Goal: keep source models explicit, labeled, and testable.

Required models or model families:

- `thin-disk-reference`
- `canonical-visible-disk-v1`
- `hotspot-orbit-v1`
- `thermal-synchrotron-toy-v1`
- `grmhd-snapshot-v1`

Every source model must document:

- assumptions
- inputs
- outputs
- known limitations
- allowed render modes
- validation scenes
- forbidden hacks

First tickets:

| Ticket | Owner | Scope | Validation |
| --- | --- | --- | --- |
| SRC-1 | Science Architect | Define the source model documentation template and promotion rules. | Source contract update. |
| SRC-2 | Implementation Agent | Add one missing source-model doc or registry entry at a time. | CLI/help and docs validation. |
| SRC-3 | Verification Agent | Audit that surrogate and legacy models are labeled correctly. | Registry audit report. |

Current baseline command:

```bash
python3 scripts/validate_source_model_registry.py
```

The registry validator now checks CLI/help/doc alignment and enforces the
Source Model Contract Matrix in `docs/source_models.md`. Each public/candidate
source row must document assumptions, inputs, outputs, known limitations,
allowed render modes, validation scenes, and forbidden hacks.

## Phase 5: Camera And Human Interpreter

Goal: make observer models scientifically inspectable instead of generic image
post-processing.

Human-eye scope:

- absolute or relative luminance
- filter or pupil assumptions
- photopic, scotopic, and mesopic weighting where implemented
- retinal adaptation
- color appearance approximation
- physiologically motivated glare or bloom
- display transform

Camera scope:

```text
scene spectral radiance
  -> lens transmission / aperture / shutter
  -> sensor quantum efficiency
  -> CFA sampling
  -> photon shot noise
  -> read noise
  -> ISO gain
  -> black level
  -> RAW buffer
  -> demosaic
  -> white balance
  -> color transform
  -> tone curve
  -> output image
```

First tickets:

| Ticket | Owner | Scope | Validation |
| --- | --- | --- | --- |
| OBS-1 | Science Architect | Define idealized eye and camera contracts before implementation. | `08_observation_pipeline_contract.md` update. |
| OBS-2 | Implementation Agent | Separate RAW-like and rendered-camera outputs if code lacks that split. | Same-radiance mode matrix. |
| OBS-3 | Verification Agent | Audit that observer work does not touch source/transfer fields. | Diff-scope report. |

Current baseline command:

```bash
python3 scripts/validate_observer_cinematic_contract.py
python3 scripts/validate_camera_raw_sidecar.py
python3 scripts/validate_scientific_raw_purity.py
```

This writes `/private/tmp/bh_observer_cinematic_contract.json` and checks the
RAW-like identity audit command surface: `camera-raw` presentation, identity
camera model/profile, linear look, fixed exposure, sensor/noise/flare/DOF off,
and background off. It also checks that analysis/debug modes zero camera
presentation effects.

The camera-raw sidecar validator writes
`/private/tmp/bh_camera_raw_sidecar/camera_raw_sidecar_metrics.json` and checks
that a `camera-raw` audit render emits a float4 linear32 radiance/depth sidecar
plus metadata through `--hdr-intermediate --hdr-out`, and an ideal
pre-demosaic RGGB float32 CFA sensor RAW buffer through `--camera-raw-out`.
It also converts the same linear32 buffer into a reference
`bayer-rggb-u16` sensor/ADC RAW sidecar with documented QE, photon/read noise,
ISO gain, ADC quantization, and black/white levels. This is stronger than a
display PNG audit and establishes a first dedicated sensor RAW buffer family.
It is still not a proprietary RAW container or named-camera calibration
profile.

The scientific/RAW purity validator writes
`/private/tmp/bh_scientific_raw_purity.json` and statically audits the Swift
parser defaults, compose policy zeroing, Metal effect gates, GUI command
generation, and GUI matrix. It is a fast guard against camera/profile
transforms and presentation-effect leakage; it does not replace pixel-level
invariance tests or the camera RAW sidecar validator.

## Phase 6: Cinematic Layer

Goal: allow film-grade presentation only after physical and observer contracts
remain intact.

Allowed:

- bloom
- lens flare
- film look
- color grading
- framing

Forbidden:

- changing physics buffers
- changing source morphology
- hiding geodesic or transfer defects
- using cinematic output as the only proof of improvement

First tickets:

| Ticket | Owner | Scope | Validation |
| --- | --- | --- | --- |
| CIN-1 | Science Architect | Define cinematic effect boundaries and required off-switches. | Render-mode contract update. |
| CIN-2 | Implementation Agent | Implement one isolated effect or diagnostic at a time. | Bloom/glare-only and no-effect outputs. |
| CIN-3 | Verification Agent | Prove scientific and RAW-like outputs remain stable. | Before/after metrics. |

The same `validate_observer_cinematic_contract.py` command records a
cinematic-on command and verifies that the off-switch path remains explicit.
`validate_scientific_raw_purity.py` complements it with a static check that
scientific and RAW-like routes keep presentation effects out of their default
and GUI-generated commands.
Pixel-level compose-path validation is covered by:

```bash
python3 scripts/validate_cinematic_pixel_invariance.py
```

This writes `/private/tmp/bh_cinematic_pixel_invariance/pixel_invariance_metrics.json`
and verifies that `camera-raw` defaults match the explicit identity RAW-like
off-switch route for a synthetic radiance/depth buffer. It also records the
scientific PNG comparison separately, while cinematic-on output differs only in
the cinematic presentation run. It is still a compose-only test, not a full
black-hole source render.

The source-render counterpart is:

```bash
python3 scripts/validate_blackhole_presentation_invariance.py
python3 scripts/validate_presentation_source_matrix.py
```

This writes
`/private/tmp/bh_blackhole_presentation_invariance/blackhole_presentation_metrics.json`
and repeats the same presentation isolation checks on the canonical black-hole
source at low resolution.

The source matrix validator writes
`/private/tmp/bh_presentation_source_matrix/presentation_source_matrix_metrics.json`
and applies the same source-render isolation checks to the recommended/candidate
thin-disk source models.

The GRMHD data-backed promotion suite is:

```bash
python3 scripts/validate_grmhd_presentation_fixture.py --suite --require-data
```

It writes
`/private/tmp/bh_grmhd_presentation_fixture/grmhd_presentation_fixture_metrics.json`
and runs the same presentation isolation checks on
`grmhd-temperature-flow-diagnostic` across multiple local HDF5 fixtures when
available. It remains separate from the fast matrix because GRMHD fixtures
depend on local data availability and snapshot conversion/cache cost.

## Default Next Branch Order

```text
codex/validation-lab-v1
codex/physics-realism-v1
codex/camera-interpreter-v1
codex/integration/physics-camera-v1
```

Reason:

1. validation-lab defines the tests that catch plausible-but-wrong changes
2. physics-realism improves source and transfer inside those tests
3. camera-interpreter consumes stable radiance
4. integration resolves boundary issues only after both sides have evidence

## Merge Rule

No implementation phase is complete until it has:

- a contract reference
- a narrow ticket
- diagnostics or scalar checks
- performance evidence when runtime behavior changes
- Verification Agent result
- integration decision with residual risks

Final full-scope audit:

```bash
python3 scripts/validate_phase_completion_audit.py
```

This command is stricter than readiness validation. It is allowed and expected
to fail while any required Phase 0-6 or GUI end-state gap remains.
