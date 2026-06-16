# Render Modes

Render modes are labels for output interpretation, not permission to change the
underlying physical scene.

## Canonical Modes

| Mode | Layer | Purpose | May change |
| --- | --- | --- | --- |
| `scientific` | L0-L3/L4 diagnostic display | Inspect physical radiance and diagnostics with minimal presentation. | Diagnostic scaling and false color only when labeled. |
| `human-eye` / `eye` | L5 observer | Human visual adaptation and perception of the same physical radiance. | Eye response, adaptation, glare, display mapping. |
| `camera-raw` | L5 observer/device record | Idealized sensor record before camera rendering. | Exposure, aperture/shutter/ISO, sensor response/noise, RAW metadata. |
| `camera-rendered` / `camera` | L5 observer/device interpretation | Camera-processed output from the RAW-like signal. | Demosaic, white balance, color transform, tone curve. |
| `cinematic` / `cinema` | L6 presentation | Film-grade final presentation. | Bloom, flare, film look, grading, framing. |
| `legacy` | reproduction | Reproduce old renderer behavior. | Only the documented compatibility path. |

## Mode Invariants

- `scientific` is the audit source. It must not contain hidden cinema fixes.
- `human-eye`, `camera-raw`, `camera-rendered`, and `cinematic` consume the same
  physical radiance unless a contract explicitly says otherwise.
- `camera-raw` and `camera-rendered` must remain separable. RAW is a device
  record; rendered is a color/tone interpretation.
- `cinematic` must be last.
- `legacy` must be labeled and should not become the recommended science path
  without a new source contract.

## Required Comparison Sheet

Any change that affects output appearance should include a matrix like:

```text
source model x render mode

canonical-visible-disk-v1:
  scientific, human-eye, camera-raw, camera-rendered, cinematic

reference or legacy source:
  scientific, human-eye, camera-raw, camera-rendered, cinematic
```

If a mode does not yet exist in code, the report should say so. Do not fake a
mode by reusing another mode without labeling it.

Current implementation note:

- `camera-raw` is accepted by the CLI as a first-class presentation name. It
  routes through the identity RAW audit path and can emit both a float4
  linear32 radiance/depth sidecar with `--hdr-intermediate --hdr-out` and an
  ideal pre-demosaic RGGB float32 CFA sensor record with `--camera-raw-out`.
  The same converter also supports `--camera-raw-format bayer-rggb-u16`,
  which writes a documented reference sensor/ADC RAW sidecar with QE,
  photon/read noise, ISO gain, black/white levels, and 16-bit ADC
  quantization. These are dedicated sensor RAW buffers, not proprietary camera
  RAW containers or named-camera profiles.
- If a source model has a filmic default look, `camera-raw` and `scientific`
  must still default to `linear` unless the user explicitly passes `--look`.
  This prevents source-model presentation defaults from contaminating the audit
  route.
- `camera-rendered` is accepted by the CLI as a first-class presentation name
  and routes to rendered camera interpretation. It remains separate from
  `cinema`, which is the L6 cinematic grade.

Policy validation:

```bash
python3 scripts/validate_run_pipeline_look_policy.py
```
