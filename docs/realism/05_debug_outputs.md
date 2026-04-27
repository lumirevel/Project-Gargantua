# Debug Outputs

Debug outputs must clarify whether a change affects physics or interpretation.

## Currently Observed Debug Outputs

The current codebase includes or references diagnostics such as:

- GRMHD scalar debug views via `diskGrmhdDebugView`
- source/radiance previews
- branch isolated previews in compose helpers
- HDR/linear32 intermediate input and output paths
- presentation validation sheets from scripts
- room RT arbitrary HDR validation through `--compose-hdr-in`
- eye/cinema/scientific comparison outputs

## Missing Or Incomplete Debug Outputs

The following should be added carefully when needed:

- explicit hit mask image
- explicit optical depth image for all relevant source models
- explicit redshift/g-factor image for canonical visible disk renders
- emission radius/source-location proxy for all source modes
- raw radiance image before tone mapping
- tone-mapped-no-bloom output
- bloom-only/glare-only output
- exposure/adaptation debug state
- multi-layer depth/radiance buffers for physically stronger camera DOF

## Adding Debug Outputs Safely

- Do not pollute final rendering paths.
- Prefer debug flags, separate output files, or validation scripts.
- Do not change buffer layouts unless the contract impact is reviewed.
- Name outputs so the layer is obvious.

## Naming Convention

Recommended generated output names:

- `physics_raw_radiance.png`
- `physics_optical_depth.png`
- `physics_redshift_gfactor.png`
- `physics_hit_mask.png`
- `physics_emission_radius.png`
- `interpreter_tone_mapped_no_bloom.png`
- `interpreter_bloom_only.png`
- `interpreter_exposure_debug.json`
- `comparison_scientific_eye_cinema.png`

Use `physics_` for source/transfer diagnostics and `interpreter_` for presentation diagnostics.
