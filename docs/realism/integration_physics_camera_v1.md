# Integration: Physics + Camera V1

## Purpose

`codex/integration/physics-camera-v1` is a temporary integration and validation branch for combining the physics realism work with the interpreter/camera realism work.

This branch exists for:

- conflict resolution experiments
- integration validation
- checking that physical source/transfer outputs remain separate from camera/interpreter presentation
- producing comparison evidence before any reviewed merge back to the shared baseline

This branch must not be used as a long-lived development branch.

## Merge Targets

Base branch:

- `codex/realism-rendering`

Feature branches planned for integration:

- `codex/physics-realism-v1`
- `codex/interpreter-camera-v1`

## Planned Merge Order

1. Merge `codex/physics-realism-v1` first.
2. Validate physical renderer outputs and render-contract fields.
3. Merge `codex/interpreter-camera-v1` second.
4. Validate that interpreter/camera changes consume physical outputs without changing source physics.

No feature branch has been merged into this integration branch yet.

## Validation Gate

Before this integration branch can be considered successful, run and record evidence for:

- clean build
- baseline scientific render
- eye render from the same source radiance
- cinema render from the same source radiance
- raw radiance or equivalent physical light signal where available
- redshift / g-factor diagnostic where available
- optical-depth or transfer diagnostic where available
- hit mask or source-location proxy where available
- tone-mapped-no-bloom output if available
- bloom/glare-only or camera-effect isolated output if available
- confirmation that generated images are not committed

Validation must show that improvements come from the correct layer:

- physics branch changes should improve physical source/transfer diagnostics
- interpreter branch changes should improve camera/eye/cinema interpretation without modifying physical source values

## Forbidden Commits

Do not commit:

- generated output images or videos
- render output directories
- DerivedData
- build products
- `.build` artifacts
- logs
- temporary files
- secrets
- credentials
- API keys
- private tokens
- `.env` files
- private machine-local configuration

## Prohibited Actions

Do not use this branch to bypass review of risky shared files such as packed Metal ABI, render resource ownership, or broad CLI changes.

Do not force push.
Do not run destructive cleanup commands.
Do not merge feature branches until explicitly requested.
