# Next Model Handoff: Realism Integration

Date: 2026-06-10

Branch: `codex/integration/physics-camera-v1-legacy-recovery`

Current HEAD: `11a728d Improve plausible cinematic disk source diagnostics and search`

Status summary:

- The branch is an integration branch containing both `origin/codex/physics-realism-v1` and `origin/codex/interpreter-camera-v1`.
- The local branch is ahead of origin by one commit.
- The worktree is dirty. No files are staged.
- The current uncommitted code changes are source-side PCD changes, not camera/post changes.
- Promotion is not ready yet. The main blockers are source/diversity validation, raw-radiance vs scientific-display separation, and missing GRMHD image-level smoke validation.
- Follow-up recovery on 2026-06-10 installed the missing Xcode Metal Toolchain and restored Release build validation.

## Files To Review

Tracked modifications:

- `Blackhole/Metal/Compose/helpers.metalh`
  - Profile-6 `physics-constrained-cinematic-disk-v1` source fields were strengthened.
  - Density, spiral, clump, hot-crescent, activity, emissivity, opacity, tau, temperature, and related debug proxies now respond more strongly to PCD controls.
  - Review `pcdConservationLift`: despite the name, it adds source energy. Validate against raw radiance before accepting it as a physical budget term.
- `Blackhole/run_pipeline.sh`
  - PCD defaults were made more structurally active:
    - `pcd-emissivity-scale=1.22`
    - `pcd-structure-scale=1.45`
    - `pcd-spiral-amp=0.42`
    - `pcd-clump-contrast=0.52`
    - `pcd-hot-crescent=0.55`

Untracked commit candidates:

- `docs/realism/accretion_disk_workflow_v1.md`
- `docs/realism/cli_option_cleanup_v1.md`
- `docs/realism/first_merge_verification_v1.md`
- `docs/realism/flat_disk_failure_analysis_v1.md`
- `docs/realism/legacy_disk_model_recovery_v1.md`
- `docs/realism/plausible_cinematic_disk_integration_report_v1.md`
- `docs/realism/source_field_repair_scientific_linear_v1.md`
- `scripts/search_disk_appearance.py`
- `scripts/validate_cli_surface.py`
- `scripts/validate_legacy_disk_models.py`

Do not stage without explicit review:

- `hello*.exposure_debug.json`
- `--disk-mode`
- `.claude/`
- generated render outputs, DerivedData, build products, logs, or private temp files

Recovery note:

- `hello*.exposure_debug.json` and `--disk-mode` were moved to `/private/tmp/blackhole_repo_quarantine_20260610_2244`.
- `.claude/` was not moved because it is a registered Git worktree for branch `claude/pedantic-yonath-86d5a9`.
- Stale missing `/private/tmp` worktree registrations were pruned with `git worktree prune`.

## Validation Run In This Handoff Pass

Passed:

```bash
bash -n Blackhole/run_pipeline.sh
python3 -m py_compile scripts/search_disk_appearance.py scripts/search_plausible_cinematic_disk.py scripts/validate_cli_surface.py scripts/validate_legacy_disk_models.py scripts/validate_physics_constrained_cinematic_disk.py
git diff --check
python3 scripts/validate_cli_surface.py
```

Recovered:

```bash
xcodebuild -project Blackhole.xcodeproj -scheme Blackhole -configuration Release -derivedDataPath /private/tmp/ProjectGargantuaHandoffDerivedData build
```

This originally failed because the local Xcode install could not execute the Metal compiler:

```text
error: cannot execute tool 'metal' due to missing Metal Toolchain; use: xcodebuild -downloadComponent MetalToolchain
```

It was recovered with:

```bash
xcodebuild -downloadComponent MetalToolchain
```

After recovery, Release build and packed ABI validation passed:

```bash
xcodebuild -project Blackhole.xcodeproj -scheme Blackhole -configuration Release -derivedDataPath /private/tmp/ProjectGargantuaHandoffDerivedData build
/private/tmp/ProjectGargantuaHandoffDerivedData/Build/Products/Release/Blackhole --validate-packed-abi --print-packed-layout
BH_DERIVED_DATA_PATH=/private/tmp/ProjectGargantuaHandoffDerivedData bash Blackhole/run_pipeline.sh --source-model physics-constrained-cinematic-disk-v1 --presentation scientific --look linear --quality preview --width 80 --height 45 --output /private/tmp/bh_handoff_recovery_pcd_smoke.png --no-build
```

Observed packed layout after recovery:

```text
PackedParams.layout size=672 stride=672 align=16
CollisionInfo.layout size=64 stride=64 align=16
CollisionLite32.layout size=32 stride=32 align=16
ComposeParams.layout size=320 stride=320 align=16
ComposeSolveParams.layout size=32 stride=32 align=4
ComposeSolveResult.layout size=32 stride=32 align=4
PackedParams.offset pcdSourceA=624
PackedParams.offset pcdSourceB=640
PackedParams.offset pcdSourceC=656
```

PCD runtime smoke output:

- `/private/tmp/bh_handoff_recovery_pcd_smoke.png`

## Current Progress

Completed or documented:

- Physics and interpreter branch inclusion was previously verified at graph/file/ABI/CLI levels.
- Legacy disk-model behavior was restored and documented:
  - `perlin`
  - `perlin-classic`
  - `perlin-ec7`
- CLI help was split into public/topic/legacy/advanced layers.
- `physics-constrained-cinematic-disk-v1` has profile-6 controls and validation scripts.
- Source-field repair A/B was documented as passing:
  - activity RMSE `0.1542`
  - density RMSE `0.0497`
  - emissivity RMSE `0.1578`
  - final RGB RMSE `0.0260`
  - high-Doppler asymmetry ratio `37.20`

Not completed:

- Current uncommitted PCD changes have only a minimal 80x45 runtime smoke render; full diagnostic A/B validation has not been rerun.
- Raw radiance / fixed exposure comparison has not been rerun after the latest PCD changes.
- GRMHD image-level smoke for `optical_depth`, `transfer-saturation`, and `emissivity-pre-transfer` remains incomplete.
- Plausible cinematic disk promotion remains blocked by morphology diversity. Earlier search passed science gates but produced only two distinct top clusters.

## Next Tasks For Other Models

1. Fix or verify the local Metal toolchain.

   The next model should first make the build environment capable of compiling Metal, or move to an environment where the Metal toolchain is present. Then rerun Release build and ABI validation.

2. Revalidate the current uncommitted PCD source changes.

   Suggested commands:

   ```bash
   xcodebuild -project Blackhole.xcodeproj -scheme Blackhole -configuration Release -derivedDataPath /private/tmp/ProjectGargantuaSourceRepairDerivedData build
   /private/tmp/ProjectGargantuaSourceRepairDerivedData/Build/Products/Release/Blackhole --validate-packed-abi --print-packed-layout
   BH_DERIVED_DATA_PATH=/private/tmp/ProjectGargantuaSourceRepairDerivedData python3 scripts/validate_physics_constrained_cinematic_disk.py --width 160 --height 90 --out-dir /private/tmp/bh_pcd_source_repair_ab2 --no-build
   ```

3. Separate source energy from display scaling.

   Run a fixed-exposure/raw-radiance comparison for `no_structure`, default, and `high_structure`. If raw radiance is also dimmer under high structure, adjust the source energy budget. If raw radiance is healthy but PNG output is dim, inspect scientific display/output scaling without changing source morphology.

4. Rerun diversity search after validating source response.

   Suggested command:

   ```bash
   BH_DERIVED_DATA_PATH=/private/tmp/ProjectGargantuaSourceRepairDerivedData python3 scripts/search_plausible_cinematic_disk.py --count 12 --top 3 --width 160 --height 90 --out-dir /private/tmp/bh_pcd_goal_search --no-build
   ```

   Promotion should require at least three distinct scientifically passing top candidates.

5. Complete GRMHD debug image smoke before integration promotion.

   Required debug views:

   - `optical_depth`
   - `transfer-saturation`
   - `emissivity-pre-transfer`

   These must produce actual bounded-time images, not just parser or ABI success.

## Risk Notes

- `physics-constrained-cinematic-disk-v1` remains a physics-constrained surrogate, not real GRMHD.
- The current source changes live in `Compose/helpers.metalh`, which is a presentation-adjacent file. Reviewers must judge by ownership of values: these changes alter source radiance/proxies, not exposure, bloom, tone mapping, or camera response.
- Do not solve low contrast or dim output by changing interpreter settings unless raw radiance proves the source is already physically healthy.
- Keep generated outputs in `/private/tmp` or another non-repository directory.
