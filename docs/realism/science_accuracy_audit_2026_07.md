# Scientific Accuracy Audit — 2026-07

Date: 2026-07-03

Branch: `science-accuracy-audit` (from `codex/realism-rendering` @ `48f76a0`, the PR #7 merge)

## Goal

Re-verify the scientific accuracy of the renderer after the GUI-Improvement merge
(warm-serve preview speedups, fast drag-grade trace profile, reconfig scoping).
The fast trace profile is serve-only and opt-in per request; this audit confirms
the physics, color science, and presentation-isolation contracts all still hold
on the merged tip.

## Environment

- Tree identity: merge commit `48f76a0^{tree}` == `7f1c050^{tree}`
  (`527483fafd9c…`) — the merged tip is byte-for-byte the audited branch code.
- Fresh isolated build: `BH_DERIVED_DATA_PATH=/tmp/BlackholeDD_science`
  (never `--no-build` against a shared path; see the stale-binary trap in
  `legacy_disk_model_recovery_v1.md`).
- GRMHD fixture data: in-repo `data/grmhd/SANE_a0_torus.out0.05010.h5`.
- All validators run sequentially, no orchestration, reports under `/private/tmp`.

## Results — 15/15 PASS + byte guardrail

| # | Validator | Scope | Result |
|---|-----------|-------|--------|
| 1 | `validate_scientific_raw_purity.py` | static parser/policy/GUI/Metal gate audit: presentation effects stay off scientific & camera-raw routes | PASS (0 failures) |
| 2 | `validate_cie_cmf_accuracy.py` | CIE 1931 CMF table vs published Planckian locus | PASS (table ≤ 0.0015 xy; Gaussian-fit worst 0.00234 noted, informational) |
| 3 | `validate_geodesic_scalar_baseline.py` | Kerr null/Lz/Q invariants, Kerr(a=0) == Schwarzschild BL metric, Hamiltonian trajectory fixture | PASS (11/11 hard cases, 9 stress cases bounded) |
| 4 | `validate_transfer_gfactor_maps.py` | renderer-produced g-factor & beaming maps: Doppler asymmetry ordering | PASS |
| 5 | `validate_presentation_modes.py` | scientific/eye/cinema separation on canonical-visible-disk-v1 | PASS (cinema morphology corr vs scientific 0.993/0.998) |
| 6 | `validate_blackhole_presentation_invariance.py` | pixel-level presentation isolation, real source render | PASS (0 failures) |
| 7 | `validate_cinematic_pixel_invariance.py` | Phase 5/6 pixel-level presentation isolation | PASS (0 failures) |
| 8 | `validate_grmhd_presentation_fixture.py` | GRMHD data-backed presentation isolation gate | PASS (0 failures) |
| 9 | `validate_legacy_disk_models.py` | legacy `--disk-model` family distinctness (perlin/classic/ec7/…) | PASS (min MAE 0.0015 / RMSE 0.003 thresholds) |
| 10 | `validate_observer_cinematic_contract.py` | observer/cinematic contract | PASS |
| 11 | `validate_render_mode_contract.py` | render mode contract | PASS |
| 12 | `validate_presentation_source_matrix.py` | presentation x source matrix | PASS |
| 13 | `validate_source_model_registry.py` | source model registry | PASS |
| 14 | `validate_realism_contract_docs.py` | contract docs consistency | PASS |
| 15 | `validate_camera_raw_sidecar.py` | camera RAW sidecar (RGGB float32 CFA + u16 sensor/ADC) | PASS |

Byte guardrail: `--preset interstellar --width 220 --height 140` final render
md5 `e0066d3fbd2784f98d8806cad3b3cf0c` — identical to the pre-GUI-Improvement
baseline. The one-shot (non-serve) render path is untouched by the preview work.

## Serve fast-profile spot checks (from the pre-merge review, same tree)

- Serve full frames byte-identical to the previous binary; fast↔full round
  trip leaves no state behind (`full == full2` md5).
- GRMHD volumetric fast frame intact (h×4 preserves path length, so the
  maxSteps/4 budget does not black out the emitting volume).
- Legacy tile-first source: no tearing across ladder resolutions, ladder-top
  full frames repeatable byte-identical.

## Verdict

The merged `codex/realism-rendering` tip preserves every audited scientific
contract. The interactive-preview fast profile degrades only opt-in, drag-time
frames; every settled frame and every file-producing render path is exact.

## Reproduce

```bash
xcodebuild -scheme Blackhole -configuration Release -derivedDataPath /tmp/BlackholeDD_science build
export BH_DERIVED_DATA_PATH=/tmp/BlackholeDD_science
python3 scripts/validate_scientific_raw_purity.py
python3 scripts/validate_cie_cmf_accuracy.py
python3 scripts/validate_geodesic_scalar_baseline.py
python3 scripts/validate_transfer_gfactor_maps.py
python3 scripts/validate_presentation_modes.py
python3 scripts/validate_blackhole_presentation_invariance.py --no-build
python3 scripts/validate_cinematic_pixel_invariance.py --no-build
python3 scripts/validate_grmhd_presentation_fixture.py
python3 scripts/validate_legacy_disk_models.py            # builds its own isolated DD
python3 scripts/validate_observer_cinematic_contract.py
python3 scripts/validate_render_mode_contract.py
python3 scripts/validate_presentation_source_matrix.py
python3 scripts/validate_source_model_registry.py
python3 scripts/validate_realism_contract_docs.py
python3 scripts/validate_camera_raw_sidecar.py --no-build
./Blackhole/run_pipeline.sh --preset interstellar --width 220 --height 140 --no-build --output /tmp/guard.png
md5 -q /tmp/guard.png   # expect e0066d3fbd2784f98d8806cad3b3cf0c
```
