# Validation Matrix

Validation must compare physics outputs and interpreter outputs separately.

## Required Comparison Outputs

Use these outputs where available:

- `final_rgb`
- `raw_radiance`
- `optical_depth`
- `redshift`
- `hit_mask`
- `emission_radius_or_source_proxy`
- `tone_mapped_no_bloom`
- `bloom_only`
- `exposure_debug` if available
- any existing diagnostic maps

## Test Scenes / Presets

Use a small matrix rather than one beauty render:

- baseline visible disk
- high inclination disk
- thin luminous layer candidate
- bright disk exposure stress test
- low brightness dynamic range test
- bloom/glare stress test
- black background / high contrast stress test

## Physics Branch Validation

Physics changes should provide at least:

- raw radiance before/after
- optical depth or transfer diagnostic if relevant
- redshift/g-factor map if relevant
- hit mask/source-radius comparison
- explanation of physical assumptions

## Interpreter Branch Validation

Interpreter changes should provide at least:

- same input radiance through scientific, eye, and cinema modes
- tone-mapped-no-bloom output
- bloom-only or glare-only output when applicable
- exposure debug or adaptation state when applicable
- a familiar non-black-hole HDR scene when validating camera/eye behavior

## Acceptance Rule

A final image is not accepted because it looks better alone. It is accepted when diagnostics show whether the improvement came from physical source/transfer correctness or downstream interpretation.
