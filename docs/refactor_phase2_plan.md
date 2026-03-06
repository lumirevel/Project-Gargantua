# Refactor Phase 2 Plan

Date: 2026-03-06
Branch: codex/refactor-modularize
Baseline report: /tmp/bh_regression/refactor_phase2_pre.json

## Intent
This pass is architectural only. It must not change legacy rendering behavior, CLI compatibility, Metal kernel entry points, or perf-anchor behavior beyond the existing 3% threshold.

## Planned moves
1. Move user-facing policy resolution out of `Blackhole/Sources/Renderer.swift` into a typed config path.
2. Introduce `ResolvedRenderConfig` as the boundary between CLI/policy/defaulting and execution.
3. Split the current renderer monolith into setup, execution, and output layers.
4. Make `AccretionModel` own disk-physics-specific defaults/validation/build hooks without changing current runtime behavior.
5. Add fail-fast ABI validation for `PackedParams` and expose it via a dedicated CLI flag.
6. Expand regression coverage and sync docs to the actual code layout.

## Non-goals
- No new physics features.
- No changes to Metal kernel entry names or argument order.
- No behavior changes in legacy/default mode except bug fixes in internal refactor-only paths.

## Verification gates
- Existing baseline manifest must continue to pass.
- Perf anchor remains `medium_gpu_perf` from `tests/baseline/manifest.json`.
- ABI validation must be runnable independently.
- Extended regression cases can be added, but existing baseline cases remain unchanged.
