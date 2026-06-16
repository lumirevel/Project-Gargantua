# GUI Option Surface V1

The CLI is now too broad for normal interactive use. The GUI should expose a
small contract-aware surface and generate the underlying CLI command rather than
duplicating renderer logic.

## UX Shape

```text
Accretion Source
  -> Observer
  -> Camera / Cinematic Controls
  -> Render
  -> Generated CLI
```

## Source Layer

The source selector maps to either `--source-model` or a documented legacy
compatibility path.

The GUI option source of truth is:

```text
docs/realism/gui_option_manifest_v1.json
```

The SwiftUI prototype is now manifest-backed: it reads this manifest first and
uses a small fallback only when the manifest is unavailable.
`scripts/validate_gui_option_manifest.py` checks that the manifest stays aligned
with source-model docs, CLI support, and the launcher.
`scripts/validate_gui_command_matrix.py` expands every manifest source across
eye, RAW-like, rendered-camera, and cinematic intents to check that generated
command combinations preserve the source/presentation boundary.
Data-backed source entries can declare `requiresDiskHDF5` and
`defaultDiskHDF5`; the launcher then exposes a source-data path field and adds
`--disk-hdf5` to the generated command.

Recommended first GUI source entries:

- `canonical-visible-disk-v1`
- `cinematic-physical-disk-v1`
- `physics-constrained-cinematic-disk-v1`
- `thin-disk-visible-reference`
- `grmhd-surrogate-disk-v1`
- `grmhd-temperature-flow-diagnostic`
- legacy Perlin variants for reproduction

Source controls must not be hidden in camera or cinematic panes.

## Observer Layer

The first GUI version exposes:

- `Human Eye`: `--presentation eye --camera-model eye`
- `Camera`: photographic/cinematic camera route

Camera has three user-facing intents:

- Scientific RAW / Linear Audit: identity linear audit route plus ideal RGGB
  float32 CFA sidecar
- Camera Rendered: full-frame photographic output with restrained tone mapping
- Cinematic Grade: cinema profile with optional color grading, flare, and DOF

The GUI labels the first intent as scientific RAW / linear audit because the
display PNG remains an identity linear audit preview while `--camera-raw-out`
writes an ideal pre-demosaic RGGB float32 CFA buffer. `camera-rendered` is a
separate first-class presentation name for photographic camera interpretation.
Calibrated sensor physics remains a contract target in
`08_observation_pipeline_contract.md`.
For RAW GUI commands, the launcher also emits
`--hdr-intermediate --hdr-out <output>.raw.linear32f32 --camera-raw-out
<output>.bayer-rggb-f32.raw` so the user gets both a float4 linear32
radiance/depth sidecar and an ideal CFA RAW sidecar next to the display
preview.

## Current Implementation

Launch options:

```bash
tools/GargantuaLauncher/run_gui.sh
```

The same SwiftUI launcher is also promoted into the `GargantuaLauncher` macOS
app target in `Blackhole.xcodeproj`; the script remains the lightweight
development entry point. The launcher:

- presents source models in a sidebar
- groups source models into recommended/production, diagnostic/surrogate, and
  legacy sections so reproduction paths do not look like default science choices
- loads source models and camera intents from
  `docs/realism/gui_option_manifest_v1.json`
- keeps manifest/path models in `tools/GargantuaLauncher/LauncherModels.swift`
- builds CLI arguments through the side-effect-free
  `tools/GargantuaLauncher/RenderCommandPlanner.swift`
- exposes a GRMHD HDF5 snapshot field for data-backed diagnostic sources
- groups observer and camera controls by contract layer
- disables camera/cinematic adjustment controls for the scientific RAW audit
  intent
- writes linear32 and ideal RGGB CFA sidecars for scientific RAW audit renders
- generates the exact CLI command
- can copy or run the command
- writes render outputs outside the repository by default
- keeps advanced physics controls behind a validation disclosure
- keeps cinematic flare/DOF controls behind an experimental disclosure
- streams process output while rendering to avoid blocking on long logs

## Promotion Path

1. Keep the app as a thin CLI command generator.
2. Add missing render modes to the renderer contract if needed.
3. Keep the manifest bundled in the app target and mirrored in docs.
4. Keep validation and diagnostics visible in the GUI before exposing advanced
   physics controls.
5. Replace the manifest with an exported source registry once the renderer has a
   stronger canonical registry API.

Current promotion validators:

```bash
python3 scripts/validate_gui_primary_target.py
python3 scripts/validate_gui_option_manifest.py
python3 scripts/validate_gui_command_matrix.py
```

Shared GUI validation helpers live in `scripts/gargantua_gui_contract.py`.

Current status:

- primary Xcode app target exists as `GargantuaLauncher`
- the manifest is bundled into the app target as a resource
- `validate_gui_primary_target.py` verifies that renderer and Metal physics
  files are not compiled into the GUI target
