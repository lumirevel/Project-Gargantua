# Photographic Camera Controls Notes

Branch: `codex/interpreter-camera-v1`

## Scope

This note covers interpreter-side camera controls only. The implementation does
not change raw radiance generation, disk emission, transfer, geodesics, redshift,
or any black-hole physics.

## Current Controls

- `--camera-f-number <N>` already controls lens depth of field through the
  camera circle-of-confusion path.
- `--camera-iso <ISO>` now records a sensor gain intent for photographic
  exposure mode.
- `--camera-shutter <seconds|fraction>` now records shutter time. Values such
  as `0.0166667` and `1/60` are accepted.
- `--exposure-mode photographic` enables aperture/shutter/ISO exposure.
  Existing `auto` and `fixed` exposure modes are unchanged.

## Image Effects

In `photographic` exposure mode:

- f-number affects exposure by the expected inverse-square aperture relation:
  exposure is proportional to `1 / N^2`.
- f-number still affects depth of field through the existing camera lens path.
- shutter affects exposure linearly: longer shutter means more collected light.
- ISO affects output gain linearly relative to ISO 100.
- default camera noise is adjusted conservatively:
  - higher ISO increases default read-noise visibility,
  - lower photon collection from shorter shutter or smaller aperture increases
    default shot-noise visibility.

Explicit `--camera-read-noise` and `--camera-shot-noise` values are respected and
are not overridden by the photographic defaults.

## Important Limitation

Update (codex/scientific-rigor-v1): shutter speed now creates physical motion
blur for the canonical visible source via `--motion-blur-samples N`. The
time-dependent heating skin/spiral/corona branches are averaged over the real
shutter window inside compose (one `diskFlowTime` unit = `sqrt(2)*rs/c`
seconds; see `docs/realism/scientific_rigor_v1_report.md`). The geometry
default black hole has an ISCO period of ~23 s, so ordinary shutter speeds
correctly freeze the disk. Trace-side time-dependent paths (precision clouds,
GRMHD volume flows) still ignore the shutter window; full slow-light subframe
tracing remains future work.

## Diagnostics

Render metadata and exposure diagnostics now include:

- `cameraFNumber`
- `cameraISO`
- `cameraShutterSeconds`
- `cameraReadNoise`
- `cameraShotNoise`
- `photographicExposureScale`

These fields make it inspectable whether a render used camera-style exposure
rather than auto exposure.

## Validation Method

Safe validation should compare the same physical input with only camera settings
changed:

1. `--exposure-mode photographic --camera-f-number 2.8 --camera-shutter 1/60 --camera-iso 100`
2. `--exposure-mode photographic --camera-f-number 1.4 --camera-shutter 1/60 --camera-iso 100`
3. `--exposure-mode photographic --camera-f-number 2.8 --camera-shutter 1/60 --camera-iso 800`

Expected behavior:

- f/1.4 should be brighter than f/2.8 and should also have shallower DOF when
  DOF is active and a valid depth proxy exists.
- ISO 800 should be brighter than ISO 100 and have stronger default sensor noise
  unless noise is explicitly overridden.
- Existing auto and fixed exposure paths should remain visually compatible with
  previous renders.

## Risks

- Update (codex/scientific-rigor-v1): the arbitrary calibration constant has
  been replaced by ISO 12232 saturation-based absolute exposure
  (`H = q*(pi/4)*L*t/N^2`, `H_sat = 78/ISO`, `L = 683.002 * CIE-Y cd/m^2`).
  This is now a physics-unit claim for the SI visible spectral path; non-SI
  sources must declare `--camera-luminance-scale`. The old behavior remains
  under `--photographic-calibration legacy`.
- Motion blur now exists for the canonical visible source (see above); other
  source paths still render time-frozen.
- Strong DOF still depends on the quality of the depth/distance proxy.
