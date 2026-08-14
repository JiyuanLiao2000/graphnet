#!/bin/bash
#SBATCH -J TC_Test                              # 明确任务名为 TC 测试
#SBATCH -A gts-itaboada3                 # 沿用跑通的账户
#SBATCH -N 1
#SBATCH --cpus-per-task=6
#SBATCH --gres=gpu:rtx_6000:1
#SBATCH -q inferno
#SBATCH --mem-per-gpu=48G
#SBATCH --time=20:00:00                          # ⏳ 测试阶段：1 小时
#SBATCH -o /storage/home/hcoda1/4/jliao74/r-itaboada3-0/jliao74/TestReco0/Reports/TC/TC_Report-%j.out
#SBATCH --mail-type=BEGIN,END,FAIL
#SBATCH --mail-user=jliao74@gatech.edu

REPO_ROOT="/storage/home/hcoda1/4/jliao74/GraphNeT/graphnet"
cd "$REPO_ROOT"
SLURM_MPI_TYPE=pmix_v4

module load anaconda3/2022.05.0.1
conda activate graphnet
export PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True

INPUT_DIR="/storage/home/hcoda1/4/jliao74/r-itaboada3-0/jliao74/TestReco0/smoke_test/tc_input"
OUTPUT_DIR="/storage/home/hcoda1/4/jliao74/r-itaboada3-0/jliao74/TestReco0/smoke_test/tc_output_unified"

# 执行批量预测脚本
srun python workflows/reconstruction/track_cascade.py \
    --input-dir "$INPUT_DIR" \
    --output-dir "$OUTPUT_DIR" \
    --model-path "$REPO_ROOT/models/track_cascade/track_cascade_model.pth" \
    --pulsemap SplitRTCleanedInIcePulses \
    --batch-size 10 \
    --num-workers 6 \
    --max-files 1
