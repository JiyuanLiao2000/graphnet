#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 8 ] || [ "$#" -gt 10 ]; then
    echo "Usage: $0 <input_dir> <output_dir> <model_path> <pulsemap> <graphnet_root> <env_prefix> <mamba> <num_workers> [batch_size] [max_files]" >&2
    exit 2
fi

INPUT_DIR="$1"
OUTPUT_DIR="$2"
MODEL_PATH="$3"
PULSEMAP="$4"
GRAPHNET_ROOT="$5"
ENV_PREFIX="$6"
MAMBA="$7"
NUM_WORKERS="$8"
BATCH_SIZE="${9:-10}"
MAX_FILES="${10:-1}"

# This GraphNeT DataLoader always sets prefetch_factor, so zero workers is
# invalid with PyTorch 2.2. Keep request_cpus equal to this positive value.
if ! [[ "$NUM_WORKERS" =~ ^[1-9][0-9]*$ ]]; then
    echo "num_workers must be a positive integer; num_workers=0 is unsupported" >&2
    exit 2
fi
if ! [[ "$BATCH_SIZE" =~ ^[1-9][0-9]*$ ]]; then
    echo "batch_size must be a positive integer" >&2
    exit 2
fi
if ! [[ "$MAX_FILES" =~ ^(-1|[1-9][0-9]*)$ ]]; then
    echo "max_files must be -1 (all files) or a positive integer" >&2
    exit 2
fi

# Reconstruction must not inherit the IceCube conversion Python environment.
unset PYTHONHOME
unset PYTHONPATH

# HTCondor may provide a minimal PATH. micromamba run searches PATH for bash
# and then sh when it creates its activation wrapper script.
export PATH="/usr/bin:/bin:${PATH:-}"

if [ ! -x "$MAMBA" ]; then
    echo "micromamba is not executable: $MAMBA" >&2
    exit 1
fi
if [ ! -d "$ENV_PREFIX" ]; then
    echo "Reconstruction environment does not exist: $ENV_PREFIX" >&2
    exit 1
fi

# Prefer the C++ runtime shipped with the validated micromamba environment.
# This export must happen before micromamba starts Python.
export LD_LIBRARY_PATH="${ENV_PREFIX}/lib:${LD_LIBRARY_PATH:-}"
export PYTHONPATH="${GRAPHNET_ROOT}/src"
export MAMBA_ROOT_PREFIX="$(dirname "$(dirname "$ENV_PREFIX")")"

mkdir -p "$OUTPUT_DIR"

printf 'Host: %s\n' "$(hostname)"
printf 'CUDA_VISIBLE_DEVICES: %s\n' "${CUDA_VISIBLE_DEVICES:-<unset>}"
printf 'GraphNeT root: %s\n' "$GRAPHNET_ROOT"
printf 'Environment: %s\n' "$ENV_PREFIX"
printf 'Input: %s\n' "$INPUT_DIR"
printf 'Output: %s\n' "$OUTPUT_DIR"
printf 'Workers: %s\n' "$NUM_WORKERS"
printf 'Batch size: %s\n' "$BATCH_SIZE"
printf 'Maximum files: %s\n' "$MAX_FILES"

"$MAMBA" run -p "$ENV_PREFIX" \
    python "$GRAPHNET_ROOT/workflows/reconstruction/energy.py" \
    --input-dir "$INPUT_DIR" \
    --output-dir "$OUTPUT_DIR" \
    --model-path "$MODEL_PATH" \
    --pulsemap "$PULSEMAP" \
    --batch-size "$BATCH_SIZE" \
    --num-workers "$NUM_WORKERS" \
    --max-files "$MAX_FILES"
