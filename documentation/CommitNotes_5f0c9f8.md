# Changes Since Last Commit

- Generated: `2026-02-22 21:05:18 UTC`
- Base commit (`HEAD`): `3acdfab` (`documentation`)
- Scope: current working tree relative to `HEAD` (tracked diffs + untracked files/directories)

## Snapshot

- Tracked files modified: `12`
- Tracked diff stats: `408 insertions`, `137 deletions`
- Untracked additions: external tool repos, AF3 weights, submit scripts, local build artifacts, this document

## Major Themes

- Resume/retry reliability fixes for pipeline orchestration, SQLite queues, and Rosetta relax steps
- Compatibility improvements for AntiBMPNN (runner detection + FASTA naming)
- VHH partial/antibody data-path fixes that prevent invalid masks / invalid `aatype`
- New/updated Slurm submit scripts for CCL2 VHH and FOLR1 hybrid/VHH campaigns
- Environment bootstrap hardening in `load_ppiflow.sh`

## Tracked Code Changes

### Runtime / Environment

- `.gitignore`
  - Added local runtime/cache ignores for `pdbs/`, `test_runs/`, `production_runs/`, `.cache` (`.gitignore:15`, `.gitignore:16`, `.gitignore:17`, `.gitignore:19`).

- `load_ppiflow.sh`
  - Refactored module initialization with explicit module-system bootstrap and helper loaders (`load_ppiflow.sh:19`).
  - Added deterministic environment setup: module purge + `PYTHONNOUSERSITE=1` (`load_ppiflow.sh:86`, `load_ppiflow.sh:88`, `load_ppiflow.sh:92`).
  - Improved partition detection defaults (including `rhino*` -> campus path).
  - Added stricter venv activation and early dependency checks (`yaml`, `pandas`, `pytz`, `dateutil`) with a hard fail if missing (`load_ppiflow.sh:150`).
  - Improved startup diagnostics (stderr for warnings/errors, clearer mode summary, pandas version output).

### Resume / Orchestration / SQLite Robustness

- `src/pipeline/config.py`
  - `normalize_input()` now treats target concatenation as idempotent on resume when `pipeline_input.json` already contains concatenated-target metadata (`src/pipeline/config.py:163`).
  - Prevents re-concatenating target chains / remapping hotspots on resume and resolves stored paths back to absolute paths (`src/pipeline/config.py:169`).

- `src/pipeline/configure.py`
  - Delays writing `pipeline_input.json` until after state validation succeeds, preventing resume identity drift if reconfigure fails (`src/pipeline/configure.py:497`).

- `src/pipeline/orchestrate.py`
  - Added `_cap_rosetta_pool_by_item_count()` to cap Rosetta worker pool size to actual item count, reducing unnecessary queue contention (`src/pipeline/orchestrate.py:184`).
  - Runtime pool size is now adjusted before worker spawn and persisted into attempt metadata (`src/pipeline/orchestrate.py:1148`).

- `src/pipeline/work_queue.py`
  - Added env overrides for queue SQLite journal mode / busy timeout:
    - `PPIFLOW_WORK_QUEUE_SQLITE_JOURNAL_MODE`
    - `PPIFLOW_WORK_QUEUE_BUSY_TIMEOUT_MS`
    - generic fallbacks `PPIFLOW_SQLITE_*` (`src/pipeline/work_queue.py:114`)
  - Queue DB init now retries `PRAGMA journal_mode`, falls back from `WAL` -> `DELETE` on shared-fs locking protocol errors, and handles transient busy/locked conditions (`src/pipeline/work_queue.py:179`).
  - `wait_for_step()` now tolerates transient SQLite busy/locked errors and avoids misclassifying empty queue/leader states during startup (`src/pipeline/work_queue.py:1101`).

- `src/pipeline/metrics_ledger.py`
  - Added env overrides and busy-timeout handling parallel to `work_queue.py` for metrics DBs (`src/pipeline/metrics_ledger.py:86`).
  - Added `WAL` -> `DELETE` fallback and retry loop for `PRAGMA journal_mode` under shared-fs locking constraints (`src/pipeline/metrics_ledger.py:130`).

### External Tool Compatibility (AntiBMPNN / ANARCI)

- `src/pipeline/steps/external.py`
  - `SeqDesignStep` runner resolution now accepts explicit script paths and detects `Running_AntiBMPNN_run.py` in a repo directory (`src/pipeline/steps/external.py:272`, `src/pipeline/steps/external.py:281`).
  - Missing-runner error message now explicitly mentions both ProteinMPNN and AntiBMPNN runner options (`src/pipeline/steps/external.py:298`).
  - Seq/FlowPacker FASTA lookup now supports AntiBMPNN naming patterns like `<stem>|abmpnn|...fa` (`src/pipeline/steps/external.py:910`, `src/pipeline/steps/external.py:1748`).
  - `FlowPackerStep` now skips PDBs without matching FASTAs and only hard-fails if zero valid items remain, with a clearer error message (`src/pipeline/steps/external.py:1864`).

- `src/pipeline/steps/interface_enrich.py`
  - Added `anarcii` fallback support when legacy `anarci` is unavailable (`src/pipeline/steps/interface_enrich.py:229`).
  - Emits a clearer error if neither `anarci` nor `anarcii` is installed (`src/pipeline/steps/interface_enrich.py:236`).

### Antibody / VHH Data & Partial-Step Reliability

- `src/data/datasets_antibody.py`
  - Fixed overlapping mask math producing non-binary values (`2`) by clamping masks to `[0,1]` in:
    - `pos_fixed_mask` path (`src/data/datasets_antibody.py:251`)
    - `fix_sequence_mask` path (`src/data/datasets_antibody.py:503`)
  - This prevents downstream invalid `aatype` calculations / CUDA asserts in antibody/vhh partial workflows.

- `src/entrypoints/sample_antibody_nanobody_partial.py`
  - `preprocess_csv_and_pkl()` now rewrites the per-run input CSV in one pass instead of append mode (`src/entrypoints/sample_antibody_nanobody_partial.py:370`).
  - Prevents duplicated headers/rows on retries (root cause of `FileNotFoundError: 'processed_path'` in partial reruns).

### Rosetta Relax Retry / Reuse Fixes

- `src/pipeline/steps/rosetta_steps.py`
  - Added `_has_relax_output(job_dir)` helper to detect successful relax outputs (`*_0001.pdb`) (`src/pipeline/steps/rosetta_steps.py:139`).
  - `RosettaRelaxStep.run_item()` now reruns Rosetta if the log exists but the relax output is missing (fixes stale-log retry failures) (`src/pipeline/steps/rosetta_steps.py:811`).
  - `RosettaRelaxStep.run_item()` now reuses an existing promoted final relax target when `--reuse` is enabled, avoiding collisions if a retry produces a different valid relaxed structure (`src/pipeline/steps/rosetta_steps.py:844`).
  - `RosettaRelaxStep.run_full()` now only skips reuse when both log and expected relax output are present (`src/pipeline/steps/rosetta_steps.py:905`).

## Untracked Additions (Not Committed Yet)

### External Tools / Weights / Data

- `assets/external/AF3Score/`
- `assets/external/AntiBMPNN/`
- `assets/external/DockQ/`
- `assets/external/flowpacker/`
- `external_data/af3_weights/af3.bin`
- `external_data/af3_weights/af3.bin.zst`

Notes:
- These are currently outside tracked `git diff` visibility until added to git.
- Local patches inside these directories (for example AntiBMPNN runner behavior) will not appear in `git diff` until the tree is tracked.

### New Submit Scripts

- `submit_ccl2_vhh.sh` (new)
  - 5-stage Slurm submit chain with `-s/--start-job` resume support (`submit_ccl2_vhh.sh:32`, `submit_ccl2_vhh.sh:77`).
  - CCL2 VHH defaults with env-overridable AF3 thresholds (`AF3SCORE1_IPTM_MIN`, `AF3SCORE2_IPTM_MIN`, optional `AF3SCORE2_PTM_MIN`) (`submit_ccl2_vhh.sh:88`, `submit_ccl2_vhh.sh:90`, `submit_ccl2_vhh.sh:92`).
  - Uses AntiBMPNN runner + checkpoint paths in the pipeline command (`submit_ccl2_vhh.sh:103`, `submit_ccl2_vhh.sh:105`, `submit_ccl2_vhh.sh:212`).
  - Adds `--retry-failed` and `PPIFLOW_WORK_QUEUE_RETRY_FAILED` on restart-sensitive Rosetta stages (Job 2 / Job 4) (`submit_ccl2_vhh.sh:286`, `submit_ccl2_vhh.sh:287`, `submit_ccl2_vhh.sh:376`, `submit_ccl2_vhh.sh:377`).

- `submit_folr1_hybrid.sh` (new)
  - FOLR1 binder campaign submit script for `farlet`, `distal`, `lateral`, `split` hotspot sets (`submit_folr1_hybrid.sh:17`, `submit_folr1_hybrid.sh:87`).
  - 5-stage dependent Slurm workflow for binder protocol (`submit_folr1_hybrid.sh:154`, `submit_folr1_hybrid.sh:320`).

- `submit_folr1_hybrid_vhh.sh` (new)
  - FOLR1 VHH campaign submit script with the same four campaign hotspot presets (`submit_folr1_hybrid_vhh.sh:17`, `submit_folr1_hybrid_vhh.sh:90`).
  - Supports env-overridable VHH backbone count / Rosetta workers / AF3 thresholds (`submit_folr1_hybrid_vhh.sh:101`, `submit_folr1_hybrid_vhh.sh:104`, `submit_folr1_hybrid_vhh.sh:105`).
  - Resume-aware AF3 threshold recovery from prior `pipeline_input.json` (`submit_folr1_hybrid_vhh.sh:171`).
  - Adds `--retry-failed` to resume-heavy stages (Rosetta1, GPU round2, Relax+Rosetta2) and exports queue retry env for Rosetta stages (`submit_folr1_hybrid_vhh.sh:288`, `submit_folr1_hybrid_vhh.sh:289`, `submit_folr1_hybrid_vhh.sh:332`, `submit_folr1_hybrid_vhh.sh:378`, `submit_folr1_hybrid_vhh.sh:379`).
  - Job walltimes set to `7-00:00:00` for all five jobs (`submit_folr1_hybrid_vhh.sh:233`, `submit_folr1_hybrid_vhh.sh:271`, `submit_folr1_hybrid_vhh.sh:319`, `submit_folr1_hybrid_vhh.sh:361`, `submit_folr1_hybrid_vhh.sh:409`).

### Local Generated Artifacts

- `src/models/layer_norm/.ninja_deps`
- `src/models/layer_norm/.ninja_log`

### This Document

- `documentation/CHANGES_SINCE_LAST_COMMIT.md` (untracked until committed)

## Operational Impact Summary

- Resume/restart behavior is significantly safer now for:
  - target concatenation state
  - partial CSV regeneration
  - SQLite queue/metrics DB startup on shared filesystems
  - Rosetta relax retries after partial/failed prior attempts
- The new VHH submit scripts expose AF3 threshold tuning and stage restarts directly in the shell interface, which matches the recent FOLR1/CCL2 debugging workflow.
