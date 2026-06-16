# GUI Option Surface V1

The CLI is now too broad for normal interactive use. The GUI should expose a
small contract-aware surface and generate the underlying CLI command rather than
duplicating renderer logic.

## UX Shape

```text
Accretion Source
  -> Observer
  -> Eye / Camera Interpreter
  -> Render Setup
  -> Generated CLI
  -> Progress / Preview
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
- groups the workflow as physical source, observer, eye/camera interpreter,
  render setup, advanced validation, generated CLI, run progress, and preview
- separates source presets from actual user inputs such as output size, SSAA,
  camera framing, ray-bundle validation mode, exposure mode, and camera optics
- disables camera/cinematic adjustment controls for the scientific RAW audit
  intent
- exposes human-eye photometric mode, optional neutral-density filtering, and
  optional adaptation-luminance override only for the eye observer
- exposes camera-like `M`, `Auto`, `Av`, `Tv`, and fixed-`EV` workflows for
  camera-rendered and cinematic outputs while mapping them to existing CLI
  exposure routes
- exposes f-number, shutter, ISO, EV compensation, diffraction/glare controls,
  photon noise mode, PSF/read/shot-noise expert controls, optional DOF, and
  motion-blur sampling only when a camera output can use them
- keeps custom camera position/FOV/roll and ray-bundle controls behind explicit
  advanced validation sections so presets remain the default workflow
- writes linear32 and ideal RGGB CFA sidecars for scientific RAW audit renders
- generates the exact CLI command
- can copy or run the command
- writes render outputs outside the repository by default
- keeps advanced physics controls behind a validation disclosure
- keeps cinematic flare/DOF controls behind an experimental disclosure
- streams process output while rendering to avoid blocking on long logs
- shows a heuristic progress bar from process log milestones
- reloads the output PNG into a preview pane during and after rendering
- provides an approximate interactive camera-orbit control for updating
  `--camX`, `--camY`, and `--camZ`; this is a framing control, not a physical
  real-time ray-traced preview

## User Control Surface

The GUI intentionally has two layers of control:

- Presets select source models and legacy reproduction paths.
- User inputs override runtime and observer settings where the CLI already has
  a contract-backed option.

Default user inputs are conservative:

- `--ssaa 1` unless the user asks for cleaner supersampling.
- Ray bundle off unless the advanced validation section is opened.
- Source-model camera presets are preserved unless `Use custom camera/framing`
  is enabled.
- Camera RAW audit keeps camera effects disabled and writes sidecars.
- Cinematic controls remain opt-in and cannot appear for RAW audit output.

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
