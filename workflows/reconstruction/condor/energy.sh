#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 8 ]; then
    echo "Usage: $0 <input_dir> <output_dir> <model_path> <pulsemap> <graphnet_root> <env_prefix> <mamba> <num_workers>" >&2
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

# Reconstruction must not inherit the IceCube conversion Python environment.
unset PYTHONHOME
unset PYTHONPATH

# Prefer the C++ runtime shipped with the validated micromamba environment.
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

"$MAMBA" run -n graphnet-reco \
    python "$GRAPHNET_ROOT/workflows/reconstruction/energy.py" \
    --input-dir "$INPUT_DIR" \
    --output-dir "$OUTPUT_DIR" \
    --model-path "$MODEL_PATH" \
    --pulsemap "$PULSEMAP" \
    --batch-size 10 \
    --num-workers "$NUM_WORKERS" \
    --max-files 1
