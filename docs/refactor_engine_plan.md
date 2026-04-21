# Engine Refactor Priority Plan

Date: 2026-04-12
Branch: codex/refactor-modularize

## Immediate Priority
The first execution split is complete. The next urgent step is not another broad file move; it is reducing the remaining long execution boundaries where policy, resource lifetime, and pass-specific details still meet.

Current hotspots:
- `Blackhole/Sources/Params/ParamsBuilder.swift`: still the longest Swift policy/defaulting boundary.
- `Blackhole/Sources/Render/Compose/RenderComposeLegacyPhase.swift`: still mixes legacy tiled compose orchestration, exposure, and readback details.
- `Blackhole/Sources/Render/Compose/RenderComposeFullGPUPhase.swift`: full-compose allocation fallback and pass submission are still tightly coupled.
- `Blackhole/Metal/volume_rt.metal`: trace orchestration remains large even after moving volume helpers out.
- `Blackhole/Metal/Compose/helpers.metalh`: compose support code is now isolated but still long.

## Ordered Refactor
1. Extract render resource policy
   - introduce a typed execution-planning boundary for:
     - collision vs hdr32 intermediate path
     - direct hdr trace preference
     - lite32 safety
     - working-set-based fallback decisions
     - trace-path summary strings
   - status: done through `RenderResourcePolicy` and `RenderExecutionPlan`

2. Split pass submission by phase
   - trace submission
   - prepass / histogram submission
   - compose submission
   - output flush
   - status: done at first pass through `Render/Trace/` and `Render/Compose/`

3. Introduce a real runtime resource manager
   - own full-frame vs tiled intermediate allocation
   - own in-flight slot allocation
   - own collision/hdr buffers and compose output buffers
   - status: partial; `RenderFrameResources` exists, but compose-specific fallback allocation should be split further

4. Add Swift-side pass wrappers
   - `TracePass`
   - `HistogramPass`
   - `ExposureSolvePass`
   - `ComposePass`
   - status: partial; trace/compose phase files exist, but histogram/exposure solve can still be smaller pass wrappers

5. Only after the above, extend thin / thick / EHT
   - Swift policy in `Core/Physics/AccretionModel.swift`
   - Metal routing in disk / volume passes

## Non-goals For This Step
- no new physics behavior
- no CLI changes
- no kernel entry renames
- no change to legacy output intent

## Success Criteria
- `RenderExecution` no longer computes execution-policy booleans inline. Done.
- Resource strategy becomes inspectable and testable on its own. Mostly done; compose fallback allocation still needs narrower seams.
- Pass extraction can proceed without re-deriving memory rules. Done for trace/compose; remaining target is histogram/exposure.
