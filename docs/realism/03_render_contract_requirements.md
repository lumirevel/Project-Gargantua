# Render Contract Requirements

The render contract is the boundary between **what exists physically** and **how it is seen**.

The physical renderer owns the contract values. The interpreter consumes them. The interpreter must not secretly modify physical values.

## Desired Intermediate Fields

Required or desired conceptual fields:

- raw radiance or physical light signal
- optical depth
- redshift / g-factor
- hit kind / hit mask
- emission radius or source-location proxy
- depth or distance proxy usable by the interpreter
- optional debug flags
- optional disk velocity if available
- optional disk normal if available
- optional temperature or temperature proxy if available

## Ownership

Physics owns:

- source radiance
- hit classification
- physical optical depth
- redshift/Doppler quantities
- source radius/location proxies
- physical debug state

Interpreter owns:

- display exposure
- eye/camera response
- sensor noise/response
- tone mapping
- bloom/glare/lens flare
- depth-of-field interpretation from source-provided depth/radiance
- final display encoding

## Current Observed Boundary

The repository already has several partial boundaries:

- `Blackhole/Metal/gr_math.metal` defines packed physical and presentation parameters shared by many kernels.
- `Blackhole/Metal/volume_rt.metal`, `Blackhole/Metal/disk_models.metal`, and `Blackhole/Metal/VolumeTransport/*` form most of the physical trace/source/transfer path.
- `Blackhole/Metal/Compose/helpers.metalh` and `Blackhole/Metal/Compose/kernels.metalh` form the presentation/compose layer.
- `Blackhole/Sources/Render/Trace/*` and `Blackhole/Sources/Render/Compose/*` are orchestration boundaries.
- `--compose-hdr-in` / linear32 HDR input is an existing practical bridge for interpreter validation on arbitrary radiance.

## Implementation Guidance

If code-level contract changes are low-risk, they may be implemented on the shared baseline. Examples:

- comments that mark ownership boundaries
- non-invasive debug labels
- documentation for existing buffer fields

If code-level contract changes are invasive, document them first and defer implementation to the appropriate branch with explicit review. Invasive examples:

- changing Metal buffer layouts
- adding fields to packed structs
- changing collision payload sizes
- changing trace/compose memory ownership
- changing direct HDR intermediate formats

## Deferred Contract Work

A fuller contract should eventually make raw radiance, depth, hit mask, optical depth, redshift/g-factor, source radius, and optional temperature/debug flags explicitly available without overloading unrelated fields. That is not implemented here because the current baseline already has many packed ABI paths, and changing them without focused review would create unnecessary breakage risk.

Transparent DOF needs an even stronger contract than a single depth proxy. A
single `float4` HDR sample cannot represent front reflection and transmitted
background at different depths. Future integration should use either explicit
multi-layer radiance/depth buffers or stochastic lens-integrated rendering.
Details are tracked in `docs/realism/multilayer_depth_render_contract_notes.md`.
