#!/bin/bash
#SBATCH -J EReco_2026                           # Energy reconstruction job
#SBATCH -A gts-itaboada3                 # Slurm account
#SBATCH -N 1
#SBATCH --cpus-per-task=6                       # CPU cores per task
#SBATCH --gres=gpu:rtx_6000:1                       # GPU allocation
#SBATCH -q inferno                              # QoS
#SBATCH --mem-per-gpu=48G                       # Memory per GPU
#SBATCH --time=20:00:00                          # Wall-time limit
#SBATCH -o /storage/home/hcoda1/4/jliao74/r-itaboada3-0/jliao74/TestReco0/Reports/E/Energy_Report-%j.out
#SBATCH --mail-type=BEGIN,END,FAIL
#SBATCH --mail-user=jliao74@gatech.edu

# Unified GraphNeT repository
REPO_ROOT="/storage/home/hcoda1/4/jliao74/GraphNeT/graphnet"
cd "$REPO_ROOT"
SLURM_MPI_TYPE=pmix_v4

module load anaconda3/2022.05.0.1
conda activate graphnet
export PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True

# Set input and output directories.
INPUT_DIR="/storage/home/hcoda1/4/jliao74/r-itaboada3-0/jliao74/TANGO_check_2026"
OUTPUT_DIR="/storage/home/hcoda1/4/jliao74/r-itaboada3-0/jliao74/TestReco0/Results_E"

# Run energy prediction on all databases.
srun python workflows/reconstruction/energy.py \
    --input-dir "$INPUT_DIR" \
    --output-dir "$OUTPUT_DIR" \
    --model-path "$REPO_ROOT/models/energy/energy_model.pth" \
    --pulsemap SplitRTCleanedInIcePulses \
    --batch-size 10 \
    --num-workers 6 \
    --max-files -1
