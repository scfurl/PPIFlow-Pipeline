#!/usr/bin/env bash
# Load PPIFlow environment (partition-aware)
# Usage: source load_ppiflow.sh

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "ERROR: source this script: source load_ppiflow.sh"
  exit 1
fi

_ppiflow_die() {
  echo "ERROR: $*"
  return 1 2>/dev/null || exit 1
}

_ppiflow_warn() {
  echo "WARNING: $*"
}

_load_module() {
  local name="$1"
  if module load "${name}" >/dev/null 2>&1; then
    return 0
  else
    return 1
  fi
}

_get_partition() {
  if [[ -n "${SLURM_JOB_PARTITION}" ]]; then
    echo "${SLURM_JOB_PARTITION}"
  else
    local hostname=$(hostname)
    case $hostname in
      harmony*) echo "chorus" ;;
      gizmo*|campus*) echo "campus" ;;
      *) echo "unknown" ;;
    esac
  fi
}

# Initialize module system
if ! type module >/dev/null 2>&1; then
  source /etc/profile.d/modules.sh || _ppiflow_die "Failed to initialize environment modules"
fi

module purge

PARTITION=$(_get_partition)
echo "Detected partition: ${PARTITION}"

# Load modules based on partition
case "${PARTITION}" in
  chorus)
    # Harmony partition - L40S GPUs with CUDA/PyTorch
    echo "Loading harmony (chorus) modules..."
    _load_module "CUDA/12.6.0" || _ppiflow_die "Failed to load CUDA/12.6.0"
    _load_module "PyTorch/2.6.0-foss-2024a-CUDA-12.6.0" || _ppiflow_die "Failed to load PyTorch/2.6.0-foss-2024a-CUDA-12.6.0"
    _load_module "HMMER/3.4-gompi-2024a" || _ppiflow_warn "Failed to load HMMER"
    _load_module "MUSCLE/5.1.0-GCCcore-12.3.0" || _ppiflow_warn "Failed to load MUSCLE"
    GPU_MODE=true
    ;;

  campus*|gizmo*)
    # Campus/Gizmo partitions - CPU only
    echo "Loading campus/gizmo modules..."
    _load_module "Python/3.12.3-GCCcore-13.3.0" || _ppiflow_die "Failed to load Python/3.12.3-GCCcore-13.3.0"
    _load_module "HMMER/3.4-gompi-2023a" || _ppiflow_warn "Failed to load HMMER"
    _load_module "MUSCLE/5.1.0-GCCcore-12.3.0" || _ppiflow_warn "Failed to load MUSCLE"
    GPU_MODE=false
    ;;

  *)
    # Unknown partition - try minimal setup
    echo "Unknown partition - loading base Python..."
    _load_module "Python/3.12.3-GCCcore-13.3.0" || _load_module "Python" || _ppiflow_warn "Could not load Python"
    GPU_MODE=false
    ;;
esac

# Activate virtual environment
source ~/.virtualenvs/ppiflow_env/bin/activate || _ppiflow_die "Failed to activate ~/.virtualenvs/ppiflow_env"

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

# Summary
echo "=========================================="
echo "PPIFlow environment loaded"
echo "=========================================="
echo "Partition: ${PARTITION}"
echo "Mode: ${GPU_MODE:+GPU}${GPU_MODE:-CPU}"
echo "Hostname: $(hostname)"
echo ""
echo "Python: $(python --version 2>&1)"
echo "PyTorch: $(python -c 'import torch; print(torch.__version__)' 2>/dev/null || echo 'Not available')"

if ${GPU_MODE:-false}; then
  echo "CUDA available: $(python -c 'import torch; print(torch.cuda.is_available())' 2>/dev/null || echo 'Check failed')"
  if command -v nvidia-smi >/dev/null 2>&1; then
    echo "GPU: $(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1 || echo 'None')"
  fi
fi

echo ""
echo "Tools:"
echo "  hmmscan: $(command -v hmmscan 2>/dev/null || echo 'not found')"
echo "  muscle: $(command -v muscle 2>/dev/null || echo 'not found')"
echo "  Rosetta: ${ROSETTA_BIN}"
echo "=========================================="
