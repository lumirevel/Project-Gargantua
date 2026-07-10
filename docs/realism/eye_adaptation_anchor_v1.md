# Eye Adaptation Anchor V1 (Narrow-Histogram White-Blob Fix)

Date: 2026-07-10

Branch: `disk-physics-improvement`

## Symptom

In the Human Eye presentation, smooth thermal disks (legacy soft perlin, thin
photospheres) displayed as a near-uniform white blob: the recovered procedural
texture was invisible ("필터가 너무 강하다"). Measured: `exposedP50 = 4.74`
with white at 0.59; ~77% of active pixels saturated; texture modulation
compressed into ~2 8-bit counts.

## Root cause (mathematical, not a tuning issue)

The physiological display is Naka-Rushton with white normalization:
`disp = R(L) / R(whiteMul * La)`, `R(L) = L^n / (L^n + La^n)`, n = 0.74.

1. Scene luminance L and adaptation La both scale with the auto-ND filter, so
   the display is **invariant to the global ND** (the ND only sets the absolute
   level for mesopic rod/cone weighting). Exposure-side fixes cannot work —
   verified empirically (identical pixel statistics under a changed ND).
2. Auto adaptation anchored La at the scene **median** (p50). The median pixel
   then sits exactly at half-response R = 0.5, and white normalization maps
   half-response to display ≈ 0.68 (gamma-encoded ≈ 214/255). The disk body of
   a narrow-histogram scene (p99.5 within ~2.5x of p50) is therefore
   structurally pinned near white — no parameter of the response can lower it.

## Fix

`RenderEyePhotometric.resolve`: the automatic adaptation anchor becomes the
**geometric mean of the median and near-peak luminance**,
`La ∝ sqrt(p50 · p995)` (explicit `--eye-adaptation` unchanged). An observer
staring at a bright disk adapts toward the bright field, not the scene median;
with this anchor the median of a narrow scene falls below half-response and
its structure re-enters the readable range, while wide-histogram scenes
(GRMHD; body spans the response range anyway) barely move.

The ineffective ND-side variant was implemented, measured to be a no-op
(display invariance above), and removed; a comment now records the invariance
so the dead knob is not rediscovered.

## Results

Session-start reproduction (`--disk-model perlin`, eye auto, 320x200):

| metric | before | after |
|---|---|---|
| saturated active px (perlin) | 77.3% | 65.9% |
| saturated active px (ec7) | 77.9% | 51.3% |
| soft-perlin texture | invisible (white blob) | visible modulation |

Presentation-modes gate (canonical visible disk, eye vs scientific):
morphology luma correlation 0.9227 → **0.9700**, gradient correlation
0.7696 → **0.9025**, eye saturated fraction 0.0307 → **0.0071** — the eye
display preserves substantially more of the physical structure.

## Verification

- Interstellar 220x140 guardrail md5 `e0066d3fbd2784f98d8806cad3b3cf0c`
  unchanged (non-eye paths untouched).
- Validators PASS: presentation_modes, grmhd_presentation_fixture (wide-
  histogram eye regression gate), scientific_raw_purity,
  blackhole_presentation_invariance.

## Scope notes

- Display-interpretation change only (L5 observer layer); no physics, no raw
  radiance, no camera paths touched.
- The precision surface-disk (`--disk-physics precision`, non-volume) renders
  through analysisMode 1/2 with fixed exposure by design; its blowout under
  camera presentations is a separate, pre-existing routing question and is
  intentionally out of scope here.
