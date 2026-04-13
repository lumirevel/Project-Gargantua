# Engine Refactor Priority Plan

Date: 2026-04-12
Branch: codex/refactor-modularize

## Immediate Priority
The next urgent step is not new physics. It is separating execution-time resource policy from pass submission.

Today the largest architectural bottleneck is `Blackhole/Sources/RenderExecution.swift`:
- it decides memory strategy
- it decides intermediate representation strategy
- it decides trace/compose path summaries
- it allocates execution resources
- it submits passes
- it flushes outputs

That is too much responsibility for the place where thin / thick / EHT work would otherwise land next.

## Ordered Refactor
1. Extract render resource policy
   - introduce a typed execution-planning boundary for:
     - collision vs hdr32 intermediate path
     - direct hdr trace preference
     - lite32 safety
     - working-set-based fallback decisions
     - trace-path summary strings
   - goal: `RenderExecution` stops owning high-level memory-policy decisions inline

2. Split pass submission by phase
   - trace submission
   - prepass / histogram submission
   - compose submission
   - output flush
   - goal: execution reads as a pipeline instead of a script

3. Introduce a real runtime resource manager
   - own full-frame vs tiled intermediate allocation
   - own in-flight slot allocation
   - own collision/hdr buffers and compose output buffers
   - goal: resource lifetime stops leaking across unrelated code paths

4. Add Swift-side pass wrappers
   - `TracePass`
   - `HistogramPass`
   - `ExposureSolvePass`
   - `ComposePass`
   - goal: future physics work changes pass inputs, not renderer structure

5. Only after the above, extend thin / thick / EHT
   - Swift policy in `AccretionModel.swift`
   - Metal routing in disk / volume passes

## Non-goals For This Step
- no new physics behavior
- no CLI changes
- no kernel entry renames
- no change to legacy output intent

## Success Criteria
- `RenderExecution` no longer computes execution-policy booleans inline
- resource strategy becomes inspectable and testable on its own
- pass extraction can proceed without re-deriving memory rules
