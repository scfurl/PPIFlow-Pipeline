# Commit Notes 

commit 68715d3


## Scope
This document summarizes the current repo changes visible in `git diff` and the rationale for each.

## Pipeline Reliability and Recovery

### `src/pipeline/work_queue.py`
- Added `_is_missing_table_error(...)` and tolerant handling in:
  - `counts()` for missing `items` table
  - `leader_status()` for missing `leader` table
- Added `PPIFLOW_WORK_QUEUE_RETRY_FAILED` env override for `retry_failed`.
- Rationale:
  - Prevents crashes during transient queue initialization/rebuild windows (`sqlite3.OperationalError: no such table: items/leader`).
  - Improves resume/retry control from orchestrator-managed worker environments.

### `src/pipeline/orchestrate.py`
- Changed default failure policy to `strict` (instead of permissive default).
- Added `_summarize_item_failures(...)` to report failed/blocked counts with representative error text.
- Made `--continue-on-error` explicitly override strict mode for that run.
- Added early failure path when workers exit but required outputs are still missing (`outputs_not_ready_after_workers_exit`).
- Wired process liveness checks into `_wait_for_ready_outputs(...)`.
- Applies failure-marker cleanup on explicit retry path.
- Rationale:
  - Avoids silent partial-success outcomes.
  - Surfaces actionable failure diagnostics immediately.
  - Prevents indefinite waits when worker pools already died.

### `src/pipeline/run_lock.py`
- Lock cleanup now only happens when ownership is provably local.
- If `owner.json` is temporarily unreadable (`active is None`), cleanup is skipped.
- Rationale:
  - Reduces risk of deleting a lock that may still belong to an active process.

### `src/pipeline/config.py`
- Added binder length parser/validator (`_parse_length_bounds`) with strict checks.
- `ppiflow_ckpt` resolution now searches both:
  - `assets/checkpoints/...`
  - `external_data/ppiflow_checkpoints/...`
- Rationale:
  - Catches malformed binder-length inputs early.
  - Makes checkpoint discovery robust across local install layouts.

### `src/pipeline/steps/external.py`
- Added robust MPNN runner resolution helpers:
  - `_mpnn_tool_keys(...)`
  - `_default_mpnn_run(...)`
  - `_require_mpnn_run(...)`
- Added checkpoint resolution/validation helpers:
  - `_resolve_seq_ckpt(...)`
  - `_require_seq_ckpt(...)`
- Added fail-fast validation in `build_items(...)`.
- Reused validated runner/ckpt resolution in `run_item(...)`, `run_batch(...)`, and `run_full(...)`.
- Rationale:
  - Fails early with precise errors for misconfigured `mpnn_run`/`abmpnn_run` and checkpoint paths.
  - Prevents expensive downstream failures caused by missing tool wiring.

## Inference Compatibility Improvements

### `scripts/flowpacker_sampler_pipe.py`
- Added `src/` path injection for local `tree` fallback support.
- Added `_torch_load_ckpt(...)` compatibility loader for Torch 2.6 (`weights_only=True` default change).
- Improved device handling for CPU/GPU portability.
- Rationale:
  - Keeps FlowPacker sampler functional across Torch versions and environments.
  - Prevents checkpoint-loading failures and CUDA-only assumptions.

### `src/tree.py` (new file)
- Added minimal local fallback for `dm-tree` implementing `map_structure`.
- Rationale:
  - Removes hard runtime dependency on `dm-tree` for current call patterns.

### `src/models/layer_norm/layer_norm.py`
- Added CPU fallback path using `torch.nn.functional.layer_norm` when input is not CUDA.
- Rationale:
  - Prevents runtime failure when fused CUDA layer norm is unavailable on CPU-only execution paths.

### `src/data/protein_dataloader.py`
### `src/experiments/inference_binder.py`
### `src/experiments/inference_antibody.py`
### `src/experiments/inference_antibody_partial.py`
### `src/experiments/utils.py`
### `src/models/flow_module_binder.py`
### `src/models/flow_module_antibody.py`
### `src/models/flow_module_antibody_partial.py`
- Added import fallbacks from `lightning` to `pytorch_lightning`.
- `inference_binder.py` trainer construction was refactored to:
  - preserve trainer config cleanly,
  - enforce CPU-safe fallback (`strategy` removed when CPU),
  - keep explicit `devices` behavior on GPU.
- `experiments/utils.py:get_available_device(...)` made robust with fallback to `torch.cuda.device_count()` when GPUtil is unavailable/fails.
- Rationale:
  - Improves portability across mixed environments where package names/APIs differ.
  - Avoids brittle trainer setup and device-discovery failures.

## CUDA Extension Artifacts (Environment-Specific)

### `src/models/layer_norm/build.ninja`
### `src/models/layer_norm/fastfold_layer_norm_cuda.so`
### `src/models/layer_norm/layer_norm_cuda.o`
### `src/models/layer_norm/layer_norm_cuda_kernel.cuda.o`
- Local rebuild artifacts reflect this machine/toolchain (CUDA 12.6, PyTorch 2.6, Python 3.12, ABI changes).
- Rationale:
  - These are generated binaries/build metadata, not portable source logic changes.

## Recommended PR Composition

### Include (source changes)
- `scripts/flowpacker_sampler_pipe.py`
- `src/tree.py`
- `src/data/protein_dataloader.py`
- `src/experiments/inference_binder.py`
- `src/experiments/inference_antibody.py`
- `src/experiments/inference_antibody_partial.py`
- `src/experiments/utils.py`
- `src/models/flow_module_binder.py`
- `src/models/flow_module_antibody.py`
- `src/models/flow_module_antibody_partial.py`
- `src/models/layer_norm/layer_norm.py`
- `src/pipeline/config.py`
- `src/pipeline/orchestrate.py`
- `src/pipeline/run_lock.py`
- `src/pipeline/steps/external.py`
- `src/pipeline/work_queue.py`

### Exclude (local/generated/runtime assets)
- `src/models/layer_norm/build.ninja`
- `src/models/layer_norm/fastfold_layer_norm_cuda.so`
- `src/models/layer_norm/layer_norm_cuda.o`
- `src/models/layer_norm/layer_norm_cuda_kernel.cuda.o`
- `src/models/layer_norm/.ninja_deps`
- `src/models/layer_norm/.ninja_log`
- `.cache/`, `test_runs/`, `runs/`
- external vendor/data directories added locally (for example `assets/external/*`, `external_data/*`) unless explicitly required by PR scope.

## Suggested PR Framing
- Theme: "Pipeline robustness + environment compatibility hardening."
- Primary impact:
  - Better failure diagnostics and safer recovery/resume behavior.
  - Better portability across Lightning/Torch/CUDA environment differences.
  - Earlier validation of external tool wiring (MPNN/AbMPNN).
