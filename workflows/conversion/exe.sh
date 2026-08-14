#!/bin/bash
echo "Starting GraphNeT conversion script..."

# 接收参数
GCD_INPUT=$1
I3_FILE=$2
OUT_DIR=$3
PULSE_KEY=$4

# ==========================================
# 核心升级：智能 GCD 文件处理模块
# ==========================================
# 我们依然建一个隔离舱，以防万一需要解压时不会弄脏工作目录
JOB_TMP_DIR=$(mktemp -d -p . tmp_job_XXXXXX)
cd "$JOB_TMP_DIR"

# 判断传入的 GCD 文件是不是 tar 压缩包
if [[ "$GCD_INPUT" == *.tar ]] || [[ "$GCD_INPUT" == *.tar.gz ]] || [[ "$GCD_INPUT" == *.tgz ]]; then
    echo "🔄 Detected tarball GCD. Extracting in isolated chamber..."
    # 解压并寻找里面的 i3 数据（兼容 .i3, .i3.gz, .i3.zst）
    tar -xf "$GCD_INPUT" --wildcards "*.i3*" 2>/dev/null
    EXTRACTED_GCD_NAME=$(ls *.i3* | head -n 1)
    GCD_FILE="$(pwd)/$EXTRACTED_GCD_NAME"
    echo "✅ Successfully extracted GCD File: $GCD_FILE"
else
    echo "⚡ Detected native GCD (.i3.gz or similar). Skipping extraction."
    # 如果不是 tar 包，直接使用原本的路径，无需解压
    GCD_FILE="$GCD_INPUT"
fi

echo "=================================================="
echo "Target I3 File : $I3_FILE"
echo "Using GCD File : $GCD_FILE"
echo "Output Dir     : $OUT_DIR"
echo "Pulse Key      : $PULSE_KEY"
echo "=================================================="

# 1. 环境配置
eval $(/cvmfs/icecube.opensciencegrid.org/py3-v4.4.2/setup.sh)
export PYTHONPATH="/data/user/jliao/software/my_custom_graphnet/src:$PYTHONPATH"

# 2. 调用 conversion.py
# 注意：因为我们刚才 cd 进了临时隔离舱，所以 conversion.py 在上一级目录 (../)
echo "Launching GraphNeT conversion..."
/data/user/mlarson/icetray/build/env-shell.sh \
/data/user/jliao/envs/mlarson_graphnet_env/bin/python3 \
-u ../conversion.py "$GCD_FILE" "$I3_FILE" "$OUT_DIR" "$PULSE_KEY"

# 3. 打扫战场
cd ..
rm -rf "$JOB_TMP_DIR"
echo "Job finished successfully and isolated directory cleaned."
