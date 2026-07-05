# Returning Radiation V1 (First-Principles Disk Self-Irradiation)

Date: 2026-07-05

Branch: `disk-physics-improvement`

## Goal

Replace the compose-stage phenomenological "returning radiation" RGB multiplier
with a physically correct, energy-conserving, trace-side model whose transfer
kernel is computed from first principles by integrating Kerr null geodesics on
the CPU. Returning radiation now enters the disk **temperature**, so it flows
through emission, redshift, and color temperature like any other heating, and
is available to the scientific NT-flux modes — not just a precision-mode
brightness trick.

## What was wrong before

`comp_precision_returning_radiation_factor` (removed) multiplied final RGB in
the compose stage by a hand-shaped factor (spin heuristic x inner-weight x
bending proxy), gated to `FC_PHYSICS_MODE == 2` only. That is physics faked in
the interpreter — exactly what `07_physics_contract.md` forbids ("changing …
emissivity … from an interpreter branch") — and it was invisible to the
scientific thin/thick modes.

## Physics model

- Disk: equatorial plane, r in [r_in, r_out], emitting the Page-Thorne NT flux
  F_NT(r) (Swift port `ReturningRadiation.ntFluxShape` mirrors the Metal
  `disk_nt_flux_shape`).
- For emitters on a log-r grid, photons launch over the comoving upper
  hemisphere (Lambertian flux weighting), with conserved (E, L) and momenta
  built from the exact circular-geodesic emitter tetrad.
- Each photon integrates the non-equatorial Kerr geodesic (Hamiltonian form,
  numeric-derivative RK4 — turning points need no sign bookkeeping) until it
  re-crosses the equatorial plane inside the disk (**returned**; deposit with
  the emit→land redshift g = -(p·u)_land folded in), crosses the horizon or
  lands inside the ISCO (**captured**), or **escapes**.
- Energy conservation: returned + captured + escaped = 1 (validated to 1e-3).
- F_tot(r) = F_NT(r) + s·F_ret(r) → T_tot(r) = T_NT(r) · E(r) with
  E = (1 + s·F_ret/F_NT)^(1/4), s = `--disk-returning-rad`.
- Multi-generation returns close geometrically up to `--disk-return-bounces`.

Units: geometric M = 1 in the transfer (massLen = rs/2); the packed LUT header
stores meters to match the shader's radii.

### Validated physics (standalone harness)

| spin | returned | captured | escaped | sum |
|------|----------|----------|---------|-----|
| 0.0  | 2.23%    | 1.24%    | 96.53%  | 1.000 |
| 0.6  | 3.78%    | 2.25%    | 93.98%  | 1.000 |
| 0.9  | 6.83%    | 3.84%    | 89.34%  | 1.000 |
| 0.998| 14.09%   | 6.44%    | 79.47%  | 1.000 |

Returning fraction rises monotonically with spin and matches the published
order (Cunningham 1976: a few % at a=0 to ~15-20% at extremal spin). The
enhancement E(r) is inner-peaked (e.g. a=0.998: ~3.6% at 1.4 r_in) and decays
outward. a=0 reduces to the Schwarzschild limit. Compute cost ~300 ms once per
render config (like the disk atlas).

## Implementation

- NEW [Blackhole/Sources/Core/Physics/ReturningRadiation.swift]: geodesic
  transfer + `packedProfile` (16-sample log-r LUT over [r_in, r_out]; the first
  bin — exactly on the zero-torque edge where F_NT→0 makes the ratio ill-posed
  — is replaced by the bounded log-r extrapolation of its neighbours).
- ABI: `PackedParams` / Metal `Params` grew a 5-field tail
  (`returnRadEnabled`, `returnRadRInM`, `returnRadInvLogSpan`, pad, 4x float4
  LUT), size 688 → 768; `--validate-packed-abi` updated and green.
- Profile computed once in `ParamsBuilder.build` after the accretion-model pack
  step; diagnostics on stderr:
  `returning-radiation: phi=… captured=… peakE=…` and the full `E(r) LUT` line
  (the pre-interpreter inspectability hook).
- Metal: `disk_returning_rad_enhancement` (disk_models.metal) evaluates the
  LUT (linear in log r; r < r_in → exactly 1, the plunge region's returned flux
  was classified captured). Applied **inside each temperature producer exactly
  once**: `thin_teff`, the precision branch of `disk_teff_thin_nt`,
  `disk_teff_legacy`, `disk_teff_thick` (outside-ISCO branch), and the
  `disk_visible_teff` wrapper — so every consumer (trace surface hits, compose
  photosphere, visible reference backbones) inherits one consistent T_tot.
- Compose fake deleted (definition + 5 call sites).
- Policy (`AccretionModel.swift`): explicit `--disk-returning-rad` /
  `--disk-return-bounces` are honored in legacy/thick/precision NT modes
  (previously warned-and-ignored outside precision). Defaults: **0 (off) for
  legacy/thick/scientific** (clean NT reference), **1.0 (full physics) for
  precision** (replacing the old 0.35 compose-fake strength). GRMHD (mode 3)
  is out of scope — its volume transfer is separate; the CPU gate never packs
  a profile there.

## Verification

- Physics: harness table above; energy conservation; spin monotonicity;
  Schwarzschild limit.
- ABI: `--validate-packed-abi` green (size 768, returnRad offsets 688/704).
- Inert-off gate: with strength 0 the interstellar 220x140 render is
  **byte-identical** (md5 `e0066d3fbd2784f98d8806cad3b3cf0c` unchanged) —
  the struct growth, injection, and fake-removal are provably inert when off.
- Wiring: `--dump-packed-params` shows enabled=0/LUT absent at strength 0 and
  the exact LUT at strength 1; a legacy-mode a=0.9 on/off render pair shows the
  inner-disk brightening (+1..+7 8-bit counts, brighter-dominated).
- Contract gates (all PASS): scientific_raw_purity,
  blackhole_presentation_invariance, cinematic_pixel_invariance,
  presentation_modes, geodesic_scalar_baseline, legacy_disk_models,
  run_pipeline_look_policy, cli_surface, presentation_source_matrix.

## Observations / limitations

- In auto-exposed presentations the smooth few-percent enhancement is largely
  absorbed by the exposure solve (a global-scale change is exactly what auto
  exposure normalizes); the physical signal lives in the raw radiance and in
  fixed-exposure/legacy renders. This is correct behavior, not a missing
  effect.
- The transfer redistributes the *locally emitted* NT flux; it does not yet
  re-lens the returning bundle's arrival direction into the observer image
  (no secondary-image contribution), and lands energy in the equatorial plane
  only (razor-thin approximation, excursion threshold 0.05 rad).
- E(r) is derived from the NT flux shape; applying it to the parametric /
  slim visible backbones is a bounded approximation (documented at the
  `disk_visible_teff` wrapper), off by default.
- The enhancement ceiling is clamped at 2.0 in temperature (16x in flux) as a
  numerical guard; physical values stay well below it everywhere except the
  ill-posed zero-flux inner bin, which is extrapolated instead.

## Reproduce

```bash
xcodebuild -scheme Blackhole -configuration Release -derivedDataPath /tmp/DD build
BIN=/tmp/DD/Build/Products/Release/Blackhole
"$BIN" --validate-packed-abi
# physics + LUT diagnostics on stderr:
"$BIN" --disk-mode thin --disk-physics precision --metric kerr --spin 0.9 \
  --camX 0 --camY -14 --camZ 2.5 --fov 55 --width 32 --height 20 \
  --presentation scientific --look linear --background off \
  --disk-returning-rad 1 --dump-packed-params /tmp/pp.bin --output /tmp/pp.png
# inert-off byte gate:
BH_DERIVED_DATA_PATH=/tmp/DD ./Blackhole/run_pipeline.sh --preset interstellar \
  --width 220 --height 140 --no-build --output /tmp/guard.png
md5 -q /tmp/guard.png   # expect e0066d3fbd2784f98d8806cad3b3cf0c
```
