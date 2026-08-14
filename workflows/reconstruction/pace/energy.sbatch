#!/bin/bash
#SBATCH -J EReco_2026                           # 明确任务名为 Energy 测试
#SBATCH -A gts-itaboada3                 # 沿用你之前跑通的账户 (或改回 gts-itaboada3)
#SBATCH -N 1
#SBATCH --cpus-per-task=6                       # 测试阶段 4 核足够了
#SBATCH --gres=gpu:rtx_6000:1                       # 测试阶段用 l40s 排队快，全量时可改回 H200
#SBATCH -q inferno                              # QOS Name
#SBATCH --mem-per-gpu=48G                       # Memory per gpu
#SBATCH --time=20:00:00                          # ⏳ 测试阶段：只申请 1 小时
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

# 定义动态输入和输出路径
INPUT_DIR="/storage/home/hcoda1/4/jliao74/r-itaboada3-0/jliao74/TANGO_check_2026"
OUTPUT_DIR="/storage/home/hcoda1/4/jliao74/r-itaboada3-0/jliao74/TestReco0/Results_E"

# 执行批量预测脚本：关闭多进程报错(num-workers=0)，开启测试阀(max-files=3)
srun python workflows/reconstruction/energy.py \
    --input-dir "$INPUT_DIR" \
    --output-dir "$OUTPUT_DIR" \
    --model-path "$REPO_ROOT/models/energy/energy_model.pth" \
    --pulsemap SplitRTCleanedInIcePulses \
    --batch-size 10 \
    --num-workers 6 \
    --max-files -1
