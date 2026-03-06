# Refactor Phase 2 Report

## What Moved
- `Renderer.swift`
  - reduced to shared math/support helpers plus orchestration entrypoint
- `RenderSetup.swift`
  - Metal device/queue/library creation
  - texture upload and pipeline specialization setup
- `RenderExecution.swift`
  - trace/light/compose execution path
- `RenderOutputs.swift`
  - image writing and metadata emission
- `AccretionModel.swift`
  - mode-specific disk policy defaults/validation boundary introduced
- `PackedParams.swift`
  - ABI validation upgraded from print-only to assertable checks

## What Did Not Move
- `ParamsBuilder.swift` still contains a large amount of general CLI-derived normalization logic.
- `RenderExecution.swift` is still large because the actual tiled render/compose path is complex and behavior-preserving extraction was prioritized over aggressive rewriting.
- Shared math helpers remain in `Renderer.swift` instead of a dedicated utility module.

## Remaining Debt
- Replace global CLI helper access with a richer typed parse result in `CLI.swift`.
- Continue shrinking `RenderExecution.swift` by extracting compose subpasses and CPU compose fallback helpers.
- Reduce warning noise from unused local destructuring in `RenderExecution.swift`.
- Add Metal-side ABI sentinel or generated ABI fixture if kernel struct layout changes become frequent.

## Verification Completed
- baseline regression manifest passes on the refactored path
- perf anchor remains within the existing 3% budget
- `--validate-packed-abi` passes with asserted size/stride/alignment/offsets

## Next Recommended Step
Implement thin/thick/EHT feature work by extending `AccretionModel.swift` and routing Metal behavior only after a matching Swift-side policy/default path exists. That keeps future physics changes from reintroducing renderer-centric branching.
