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

Shutter speed does not yet create motion blur. The current compose stage
interprets one static physical HDR input, so there is no time-sampled signal to
integrate. Motion blur should wait for a future interpreter integration that has
either temporal subframes, velocity vectors, or a reviewed motion proxy.

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

- The calibration constant maps arbitrary renderer radiance into a usable display
  range. It is an interpreter calibration, not a physics-unit claim.
- Motion blur is intentionally absent until temporal data exists.
- Strong DOF still depends on the quality of the depth/distance proxy.
