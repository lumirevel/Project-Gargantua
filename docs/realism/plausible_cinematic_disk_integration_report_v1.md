# Plausible Cinematic Disk Integration Report v1

## Target

The target is not a beautiful fake disk, and not a boring scientific reference disk. The target is the most aesthetically compelling disk within a scientifically plausible parameter space.

## Phase Results

### Phase 0. Preflight

Status: passed.

- Branch: `codex/integration/physics-camera-v1-legacy-recovery`
- `origin/codex/physics-realism-v1` is an ancestor of HEAD.
- `origin/codex/interpreter-camera-v1` is an ancestor of HEAD.
- Dirty worktree existed before this pass due prior recovery/cleanup work. No generated render outputs were intentionally staged.

### Phase 1. Goal and Acceptance Document

Status: passed.

Created:

- `docs/realism/plausible_cinematic_disk_goal_v1.md`

The document fixes the goal, prohibits production use of legacy Perlin/noise/procedural material texture, permits explicitly labeled physics-constrained surrogate fields, and requires diagnostics beyond final RGB.

### Phase 2. Source Model Implementation

Status: partially passed.

Implemented high-level source model wiring:

- `--source-model physics-constrained-cinematic-disk-v1`

The model maps to the existing clean thin/intermediate disk source path with canonical visible disk branch logic:

- thin disk body/photosphere backbone
- disk-coordinate stochastic hot-skin support from canonical realism profile
- weak corona support
- legacy Perlin/noise material texture disabled
- scientific presentation default

Validation outputs were generated at low resolution under:

- `/private/tmp/bh_physics_constrained_cinematic_v1/preview.png`
- `/private/tmp/bh_physics_constrained_cinematic_v1/diagnostic_g.png`
- `/private/tmp/bh_physics_constrained_cinematic_v1/diagnostic_emissivity.png`
- `/private/tmp/bh_physics_constrained_cinematic_v1/diagnostic_beaming.png`
- `/private/tmp/bh_physics_constrained_cinematic_v1/diagnostic_tau.png`
- `/private/tmp/bh_physics_constrained_cinematic_v1/diagnostic_hdr.png`
- `/private/tmp/bh_physics_constrained_cinematic_v1/diagnostic_activity.png`

Caveat:

The model is currently stronger as a workflow/preset and validation target than as a fully independent source implementation. Some desired physical fields are not yet direct ABI/shader parameters.

### Phase 3. Science-Gated Parameter Search

Status: infrastructure passed, diversity gate failed.

Created:

- `scripts/search_plausible_cinematic_disk.py`
- `docs/realism/plausible_cinematic_disk_search_v1.md`

Validation command:

```bash
BH_DERIVED_DATA_PATH=/private/tmp/ProjectGargantuaPlausibleCinematicDerivedData \
python3 scripts/search_plausible_cinematic_disk.py \
  --count 12 \
  --top 3 \
  --width 160 \
  --height 90 \
  --out-dir /private/tmp/bh_plausible_cinematic_disk_search \
  --no-build
```

Results:

- 12 / 12 candidates passed the science gate.
- Only 2 visually distinct top candidates were selected under the strict RMSE duplicate threshold.
- A 24-candidate extension also selected only 2 distinct top candidates, confirming a real source-parameter diversity limitation.
- Candidate JSON, command JSON, score JSON, previews, diagnostics, best params, and contact sheet were generated.

Key outputs:

- `/private/tmp/bh_plausible_cinematic_disk_search/search_report.json`
- `/private/tmp/bh_plausible_cinematic_disk_search/best_params.json`
- `/private/tmp/bh_plausible_cinematic_disk_search/top_candidates_sheet.png`

Top candidates:

| Candidate | Score | Science | Aesthetic | Active mean luma | Radial contrast | Azimuthal variance | Saturated ratio |
|---|---:|---:|---:|---:|---:|---:|---:|
| cand_11 | 0.9432 | 0.9165 | 0.9772 | 0.2223 | 2.6005 | 0.1276 | 0.0000 |
| cand_08 | 0.9146 | 0.8762 | 0.9636 | 0.2615 | 2.1916 | 0.1025 | 0.0000 |

### Phase 4. Flat Disk / Duplicate Candidate Analysis

Status: completed.

Created:

- `docs/realism/flat_disk_failure_analysis_v1.md`

Conclusion:

The candidate family is not failing because of eye/cinema presentation. The main limitation is source-model control: several scientifically meaningful parameters are not yet direct shader/ABI fields, so the search collapses into too few morphology clusters.

### Phase 5. Final Validation

Status: build/ABI/smoke passed; promotion gate failed on source diversity.

Final checks performed:

- `bash -n Blackhole/run_pipeline.sh`: passed
- Python script compilation: passed
- CLI surface validation: passed
- Xcode Release build: passed
- Packed ABI validation: passed
- preview render: passed
- diagnostic smoke images: generated
- 12-candidate search: generated, 12 / 12 science pass, 2 distinct top candidates
- 24-candidate extension: generated, 24 / 24 science pass, 2 distinct top candidates

The failure is not runtime correctness. The failure is that source morphology diversity is not broad enough for the final target.

## Changed Files

Source / scripts:

- `Blackhole/run_pipeline.sh`
- `scripts/search_plausible_cinematic_disk.py`

Documentation:

- `docs/realism/plausible_cinematic_disk_goal_v1.md`
- `docs/realism/physics_constrained_cinematic_disk_v1.md`
- `docs/realism/plausible_cinematic_disk_search_v1.md`
- `docs/realism/flat_disk_failure_analysis_v1.md`
- `docs/realism/plausible_cinematic_disk_integration_report_v1.md`

This pass also depends on earlier uncommitted recovery/cleanup files in the same worktree:

- `docs/realism/first_merge_verification_v1.md`
- `docs/realism/legacy_disk_model_recovery_v1.md`
- `docs/realism/cli_option_cleanup_v1.md`
- `docs/realism/accretion_disk_workflow_v1.md`
- `scripts/validate_cli_surface.py`
- `scripts/validate_legacy_disk_models.py`
- `scripts/search_disk_appearance.py`

## Validation Commands

Executed:

```bash
bash -n Blackhole/run_pipeline.sh
python3 -m py_compile scripts/search_plausible_cinematic_disk.py scripts/search_disk_appearance.py scripts/validate_cli_surface.py
python3 scripts/validate_cli_surface.py
```

Executed preview/diagnostic smoke:

```bash
BH_DERIVED_DATA_PATH=/private/tmp/ProjectGargantuaDiskWorkflowDerivedData \
bash Blackhole/run_pipeline.sh \
  --source-model physics-constrained-cinematic-disk-v1 \
  --presentation scientific \
  --look linear \
  --quality preview \
  --width 160 \
  --height 90 \
  --output /private/tmp/bh_physics_constrained_cinematic_v1/preview.png \
  --no-build
```

Executed diagnostics:

```bash
for dbg in g emissivity beaming tau hdr activity; do
  BH_DERIVED_DATA_PATH=/private/tmp/ProjectGargantuaDiskWorkflowDerivedData \
  bash Blackhole/run_pipeline.sh \
    --source-model physics-constrained-cinematic-disk-v1 \
    --presentation scientific \
    --look linear \
    --quality preview \
    --width 160 \
    --height 90 \
    --realism-debug "$dbg" \
    --output "/private/tmp/bh_physics_constrained_cinematic_v1/diagnostic_${dbg}.png" \
    --no-build
done
```

Executed search smoke:

```bash
BH_DERIVED_DATA_PATH=/private/tmp/ProjectGargantuaPlausibleCinematicDerivedData \
python3 scripts/search_plausible_cinematic_disk.py \
  --count 12 \
  --top 3 \
  --width 160 \
  --height 90 \
  --out-dir /private/tmp/bh_plausible_cinematic_disk_search \
  --no-build
```

## Promotion Readiness

Decision: not ready.

Reason:

- The workflow, documentation, CLI wiring, diagnostics, and search infrastructure are useful and scientifically aligned.
- Runtime/build/ABI validation passed.
- However, the explicit diversity gate failed: even 24 candidates produced only 2 distinct top morphology clusters.
- The next pass should expand the source parameter contract rather than tune presentation.

## Next Improvement

Add ABI-reviewed source fields for the production source model:

- spiral amplitude
- spiral pitch
- clump contrast
- hot crescent strength
- optical-depth/photosphere scale
- deterministic seed

Then rerun the 12-candidate search and require at least 3 distinct scientifically passing top candidates.
