# Flat / Duplicate Disk Failure Analysis v1

## Trigger

This analysis was triggered by the first `physics-constrained-cinematic-disk-v1` search smoke run.

The search produced 12 / 12 science-gate-passing candidates, but only 2 visually distinct top candidates under the default near-duplicate RMSE threshold. A 24-candidate extension also produced 24 / 24 science-gate-passing candidates but still only 2 visually distinct top candidates. That means the workflow is operational, but the parameter space is still too narrow for reliable cinematic source exploration.

## Layered Diagnosis

### 1. Source Field Analysis

Observed issue:

- `physics-constrained-cinematic-disk-v1` is currently implemented mostly as a high-level source-model preset over the existing `canonical-visible-disk-v1` thin source path.
- The canonical thin source already has a disk-coordinate spectral heating field, but several user-facing search parameters do not yet map to independent source fields.
- `hot_crescent_strength` is recorded for future reproducibility, but currently maps only indirectly through temperature, turbulence, and orbital controls.
- There is no dedicated public/source-level field for spiral amplitude, spiral pitch, clump contrast, density radial exponent, or seed in the packed ABI.

Consequence:

- Multiple sampled candidates collapse into visually similar morphology clusters.
- Search can vary brightness/temperature and some turbulence support, but cannot yet produce enough independent disk-source structures.

Physical interpretation:

- The current source is still closer to a physically constrained thin-disk reference with stochastic skin than to a broad surrogate simulation parameter space.
- This is scientifically safer than legacy Perlin material texture, but not yet expressive enough for the stated target.

### 2. Transfer Analysis

Observed issue:

- The low-res smoke diagnostics generated `emissivity`, `tau`, `hdr`, `g`, `beaming`, and `activity` maps.
- For the thin/intersection path, some diagnostics are proxies rather than full volume-transfer maps.
- There is no evidence from this pass that transfer alone is destroying structure; the similarity appears before/at source parametrization.

Likely status:

- Transfer is not the primary duplicate-candidate bottleneck.
- Diagnostics should still be improved so `optical_depth` and photosphere support are explicit for thin/intermediate source models.

### 3. Relativistic Analysis

Observed issue:

- `g`/beaming diagnostics exist and are generated.
- Doppler-compatible controls are present via orbital boost and the ray/disk intersection path.
- The search does not yet sample camera inclination or spin. That means relativistic morphology diversity is constrained.

Consequence:

- Brightness hierarchy can change, but geometric image-family diversity is limited.

Likely status:

- Relativistic transfer is functioning, but the search does not yet exercise enough physically allowed geometry/camera space.

### 4. Interpreter Analysis

Observed issue:

- The search used fixed scientific presentation with `--look linear`.
- No eye/cinema presentation was used to decide the source winner.
- There is no indication that tone mapping, bloom, or exposure caused the duplicate-candidate failure.

Likely status:

- Interpreter is not the bottleneck for this failure.
- Eye/cinema should remain downstream after source diversity improves.

## Root Cause Table

| Candidate Cause | Supported? | Evidence | First Fix |
|---|---|---|---|
| Source parameters collapse to few effective controls | Strong | 12 pass science gate but only 2 distinct morphology clusters | Add direct source/ABI fields for density, spiral, clump, seed |
| Transfer washes out all structure | Weak | Search differences are already small under source validation; no alpha/tau-specific evidence here | Add better thin-source tau/branch diagnostics |
| Relativistic effects absent | Partial | g/beaming diagnostics exist, but camera/spin/inclination not searched | Add physically bounded camera/spin search dimensions |
| Interpreter hides structure | Weak | Search used scientific/linear validation, not eye/cinema | Keep interpreter downstream |
| Legacy noise/procedural texture missing | Not a defect | Production model must not use Perlin/material texture | Do not reintroduce legacy texture |

## Top Three Fixes

1. Add explicit source-model fields for `physics-constrained-cinematic-disk-v1`.

   Needed fields:

   - density radial exponent
   - temperature exponent already present, but should be documented as source-owned
   - emissivity scale
   - optical-depth scale
   - spiral amplitude
   - spiral pitch
   - clump contrast
   - hot crescent strength
   - deterministic seed

   These require packed ABI review before implementation.

2. Strengthen thin-source diagnostics.

   Needed outputs:

   - body/source flux proxy
   - skin activity proxy
   - corona support proxy
   - branch ratios in fixed diagnostic scale
   - optical-depth/photosphere proxy for the thin/intermediate source path

3. Add geometry/camera dimensions to the search after source diagnostics are reliable.

   Safe dimensions:

   - inclination / camera preset
   - spin / ISCO setting
   - disk outer radius
   - source time sequence

   These should be added only after the source field maps can explain the final image.

## Next Codex Prompt Draft

```text
Continue on codex/integration/physics-camera-v1-legacy-recovery.
Do not touch eye/cinema first.
Implement code-level source parameters for physics-constrained-cinematic-disk-v1:
- spiral amplitude and pitch
- clump contrast
- hot crescent strength
- deterministic seed
- optical-depth/photosphere scale
Keep the clean thin-disk body and canonical visible disk path intact.
Add fixed diagnostic maps for body/source flux, skin activity, corona support, and branch ratios.
Validate packed ABI, render 12-candidate search, and require at least 3 distinct top candidates.
```

## Conclusion

The failure is not that the production direction is scientifically wrong. The failure is that this pass mostly created workflow-level source-model wiring and a science-gated search, while the underlying source model still lacks enough direct, physically meaningful control fields.

The correct next step is not bloom, tone mapping, or legacy texture. It is a small ABI-reviewed source-parameter expansion plus better source diagnostics.
