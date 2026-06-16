# Codex Common Rules For Realism Work

## Separation Rules

- Do not mix physics changes and interpreter changes unless working in a later integration branch.
- Physics branches must not solve realism with tone mapping, bloom, lens flare, exposure hacks, color grading, or aesthetic-only tricks.
- Interpreter branches must not change disk density, emissivity, opacity, geodesic integration, hit logic, redshift, optical depth, or physical transfer.
- Always preserve or improve debug visibility.
- Beauty image alone is not enough.
- Follow `06_ai_role_protocol.md`: implementation work must cite a contract or
  ticket, and verification work must audit the diff instead of rewriting scope.

## Engineering Rules

- Prefer small commits.
- Prefer small, reviewable diffs.
- Do not add many new runtime options unless necessary.
- Do not remove existing working presets without explicit reason.
- Every change must explain:
  1. what changed
  2. why it changed
  3. how to validate it
  4. what risks remain

## Apple Silicon / Swift / Metal Rules

- Keep Apple Silicon, Swift, and Metal constraints in mind.
- Avoid CPU-GPU synchronization regressions.
- Avoid unnecessary memory growth.
- Avoid changing Metal buffer layouts without checking alignment and compatibility.
- Avoid broad refactors unless they directly support branch separation or diagnostics.

## Git And Artifact Safety

- Do not commit secrets, credentials, `.env` files, private tokens, DerivedData, build products, generated render outputs, large binary artifacts, or logs.
- Do not run destructive git commands unless explicitly requested and safe.
- Generated debug images should be written outside the repository or ignored.
