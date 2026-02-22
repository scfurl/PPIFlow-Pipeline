#!/usr/bin/env bash
# Load PPIFlow environment (partition-aware, deterministic)
# Usage: source load_ppiflow.sh

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "ERROR: source this script: source load_ppiflow.sh" >&2
  exit 1
fi

_ppiflow_die() {
  echo "ERROR: $*" >&2
  return 1
}

_ppiflow_warn() {
  echo "WARNING: $*" >&2
}

_init_modules() {
  if type module >/dev/null 2>&1; then
    return 0
  fi

  local init_file
  for init_file in /etc/profile.d/modules.sh /usr/share/lmod/lmod/init/bash; do
    if [[ -f "${init_file}" ]]; then
      # shellcheck disable=SC1090
      source "${init_file}" && break
    fi
  done

  type module >/dev/null 2>&1 || {
    _ppiflow_die "Failed to initialize environment modules"
    return 1
  }
}

_load_module() {
  local name="$1"
  module load "${name}" >/dev/null 2>&1
}

_load_one_of() {
  local name
  for name in "$@"; do
    if _load_module "${name}"; then
      echo "${name}"
      return 0
    fi
  done
  return 1
}

_require_one_of() {
  local chosen
  for chosen in "$@"; do
    if _load_module "${chosen}"; then
      echo "${chosen}"
      return 0
    fi
  done
  _ppiflow_die "Failed to load one of: $*"
  return 1
}

_try_one_of() {
  _load_one_of "$@" >/dev/null 2>&1 || true
}

_get_partition() {
  if [[ -n "${SLURM_JOB_PARTITION:-}" ]]; then
    echo "${SLURM_JOB_PARTITION}"
    return
  fi

  local host
  host="$(hostname -s 2>/dev/null || hostname)"

  case "${host}" in
    harmony*|chorus*) echo "chorus" ;;
    gizmo*|campus*|rhino*) echo "campus" ;;
    *) echo "campus" ;; # safe default branch for interactive/login nodes
  esac
}

_init_modules || return 1

module --force purge >/dev/null 2>&1 || module purge >/dev/null 2>&1 || true

# Keep Python environment deterministic
unset PYTHONPATH
export PYTHONNOUSERSITE=1

PARTITION="$(_get_partition)"
GPU_MODE=0

echo "Detected partition: ${PARTITION}"

case "${PARTITION}" in
  chorus)
    echo "Loading chorus modules..."
    _require_one_of "CUDA/12.6.0" "CUDA/12.4.0" >/dev/null || return 1
    _require_one_of "PyTorch/2.6.0-foss-2024a-CUDA-12.6.0" >/dev/null || return 1
    _try_one_of "PyYAML/6.0.2-GCCcore-13.3.0"
    _try_one_of "HMMER/3.4-gompi-2024a" "HMMER/3.4-gompi-2023a"
    _try_one_of "MUSCLE/5.1.0-GCCcore-12.3.0" "MUSCLE/5.1.0-GCCcore-13.3.0"
    GPU_MODE=1
    ;;
  campus*|gizmo*)
    echo "Loading campus/gizmo modules..."
    _require_one_of "Python/3.12.3-GCCcore-13.3.0" >/dev/null || return 1
    _try_one_of "SciPy-bundle/2024.05-gfbf-2024a"
    _try_one_of "Python-bundle-PyPI/2024.06-GCCcore-13.3.0"
    _try_one_of "PyYAML/6.0.2-GCCcore-13.3.0"
    _try_one_of "HMMER/3.4-gompi-2023a" "HMMER/3.4-gompi-2024a"
    _try_one_of "MUSCLE/5.1.0-GCCcore-12.3.0" "MUSCLE/5.1.0-GCCcore-13.3.0"
    GPU_MODE=0
    ;;
  *)
    echo "Loading fallback CPU modules..."
    _require_one_of "Python/3.12.3-GCCcore-13.3.0" "Python" >/dev/null || return 1
    _try_one_of "SciPy-bundle/2024.05-gfbf-2024a"
    _try_one_of "Python-bundle-PyPI/2024.06-GCCcore-13.3.0"
    _try_one_of "PyYAML/6.0.2-GCCcore-13.3.0"
    _try_one_of "HMMER/3.4-gompi-2023a" "HMMER"
    _try_one_of "MUSCLE/5.1.0-GCCcore-12.3.0" "MUSCLE"
    GPU_MODE=0
    ;;
esac

# Activate virtual environment
TARGET_VENV="${HOME}/.virtualenvs/ppiflow_env"
if [[ -n "${VIRTUAL_ENV:-}" && "${VIRTUAL_ENV}" != "${TARGET_VENV}" ]]; then
  deactivate >/dev/null 2>&1 || true
fi
source "${TARGET_VENV}/bin/activate" || {
  _ppiflow_die "Failed to activate ${TARGET_VENV}"
  return 1
}

# Verify required Python deps early (avoids late failures in jobs)
if ! python - <<'PY'
import importlib.util as iu

missing = [m for m in ("yaml", "pandas", "pytz", "dateutil") if iu.find_spec(m) is None]
if missing:
    raise SystemExit("missing: " + ",".join(missing))
PY
then
  _ppiflow_die "Missing Python deps (yaml/pandas/pytz/dateutil)."
  return 1
fi

# Set environment variables
export PPIFLOW_ROOT=/fh/fast/furlan_s/user/sfurlan/software/PPIFlow-Pipeline
export CUDA_VISIBLE_DEVICES="${CUDA_VISIBLE_DEVICES:-0}"
export PROTEINMPNN_REPO="${PPIFLOW_ROOT}/assets/external/ProteinMPNN"
export FLOWPACKER_REPO="${PPIFLOW_ROOT}/assets/external/flowpacker"
export AF3SCORE_REPO="${PPIFLOW_ROOT}/assets/external/AF3Score"
export DOCKQ_BIN="${PPIFLOW_ROOT}/assets/external/DockQ/src/DockQ/DockQ.py"
export AF3SCORE_PYTHON="${HOME}/.virtualenvs/ppiflow_af3score/bin/python"
export AF3_DB_DIR="${PPIFLOW_ROOT}/assets/external/AF3Score/databases"
export ROSETTA_BIN=/fh/fast/furlan_s/grp/software/rosetta.binary.ubuntu.release-408/main/source/build/src/release/linux/5.4/64/x86/gcc/7/static/rosetta_scripts.static.linuxgccrelease
export ROSETTA_DB=/fh/fast/furlan_s/grp/software/rosetta.binary.ubuntu.release-408/main/database
export PATH="$(dirname "${ROSETTA_BIN}"):${PATH}"

# Verify critical tools
if ! command -v hmmscan >/dev/null 2>&1; then
  _ppiflow_warn "hmmscan not found on PATH"
fi
if ! command -v muscle >/dev/null 2>&1; then
  _ppiflow_warn "muscle not found on PATH"
fi
if [[ ! -x "${ROSETTA_BIN}" ]]; then
  _ppiflow_warn "Rosetta binary not executable at ${ROSETTA_BIN}"
fi

MODE="CPU"
if [[ "${GPU_MODE}" -eq 1 ]]; then
  MODE="GPU"
fi

echo "=========================================="
echo "PPIFlow environment loaded"
echo "=========================================="
echo "Partition: ${PARTITION}"
echo "Mode: ${MODE}"
echo "Hostname: $(hostname)"
echo
echo "Python: $(python --version 2>&1)"
echo "Executable: $(command -v python)"
echo "PyTorch: $(python -c 'import torch; print(torch.__version__)' 2>/dev/null || echo 'Not available')"
echo "Pandas: $(python -c 'import pandas; print(pandas.__version__)' 2>/dev/null || echo 'Not available')"

if [[ "${GPU_MODE}" -eq 1 ]]; then
  echo "CUDA available: $(python -c 'import torch; print(torch.cuda.is_available())' 2>/dev/null || echo 'Check failed')"
  if command -v nvidia-smi >/dev/null 2>&1; then
    echo "GPU: $(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1 || echo 'None')"
  fi
fi

echo
echo "Tools:"
echo "  hmmscan: $(command -v hmmscan 2>/dev/null || echo 'not found')"
echo "  muscle: $(command -v muscle 2>/dev/null || echo 'not found')"
echo "  Rosetta: ${ROSETTA_BIN}"
echo "=========================================="
