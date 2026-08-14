#!/bin/bash
#SBATCH -J 2026_Pred_DV              # Direction/vertex smoke-test job
#SBATCH -A gts-itaboada3        # Slurm account
#SBATCH -N 1
#SBATCH --cpus-per-task=6
#SBATCH --gres=gpu:rtx_6000:1              # GPU allocation
#SBATCH -q inferno                     # QoS
#SBATCH --mem-per-gpu=48G              # Memory per GPU
#SBATCH --time=20:00:00                 # Wall-time limit
#SBATCH -o /storage/home/hcoda1/4/jliao74/r-itaboada3-0/jliao74/TestReco0/Reports/DV/Report-%j.out               # Combined stdout and stderr file
#SBATCH --mail-type=BEGIN,END,FAIL     # Notification events
#SBATCH --mail-user=jliao74@gatech.edu # Notification address

REPO_ROOT="/storage/home/hcoda1/4/jliao74/GraphNeT/graphnet"
cd "$REPO_ROOT"
SLURM_MPI_TYPE=pmix_v4

module load anaconda3/2022.05.0.1
conda activate graphnet
export PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True

INPUT_DIR="/storage/home/hcoda1/4/jliao74/r-itaboada3-0/jliao74/TestReco0/smoke_test/dv_input"
OUTPUT_DIR="/storage/home/hcoda1/4/jliao74/r-itaboada3-0/jliao74/TestReco0/smoke_test/dv_output_unified"

# Run direction and vertex prediction on one database.
srun python workflows/reconstruction/direction_vertex.py \
    --input-dir "$INPUT_DIR" \
    --output-dir "$OUTPUT_DIR" \
    --model-path "$REPO_ROOT/models/direction_vertex/direction_vertex_model.pth" \
    --pulsemap SplitRTCleanedInIcePulses \
    --batch-size 10 \
    --num-workers 6 \
    --max-files 1                      # Process one database.
