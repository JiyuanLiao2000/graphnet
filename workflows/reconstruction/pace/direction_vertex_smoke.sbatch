#!/bin/bash
#SBATCH -J 2026_Pred_DV              # Job name (改成了 Test)
#SBATCH -A gts-itaboada3        # Charge account
#SBATCH -N 1
#SBATCH --cpus-per-task=6
#SBATCH --gres=gpu:rtx_6000:1              # Number of nodes and GPUs required
#SBATCH -q inferno                     # QOS Name
#SBATCH --mem-per-gpu=48G              # Memory per gpu
#SBATCH --time=20:00:00                 # ⏳ 测试阶段只申请 1 小时足矣
#SBATCH -o /storage/home/hcoda1/4/jliao74/r-itaboada3-0/jliao74/TestReco0/Reports/DV/Report-%j.out               # Combined output and error messages file
#SBATCH --mail-type=BEGIN,END,FAIL     # Mail preferences
#SBATCH --mail-user=jliao74@gatech.edu # e-mail address for notifications

REPO_ROOT="/storage/home/hcoda1/4/jliao74/GraphNeT/graphnet"
cd "$REPO_ROOT"
SLURM_MPI_TYPE=pmix_v4

module load anaconda3/2022.05.0.1
conda activate graphnet
export PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True

INPUT_DIR="/storage/home/hcoda1/4/jliao74/r-itaboada3-0/jliao74/TestReco0/smoke_test/dv_input"
OUTPUT_DIR="/storage/home/hcoda1/4/jliao74/r-itaboada3-0/jliao74/TestReco0/smoke_test/dv_output_unified"

# 执行批量预测脚本
srun python workflows/reconstruction/direction_vertex.py \
    --input-dir "$INPUT_DIR" \
    --output-dir "$OUTPUT_DIR" \
    --model-path "$REPO_ROOT/models/direction_vertex/direction_vertex_model.pth" \
    --pulsemap SplitRTCleanedInIcePulses \
    --batch-size 10 \
    --num-workers 6 \
    --max-files 1                      # 🚰 这里就是你的测试阀：只跑 3 个文件！
