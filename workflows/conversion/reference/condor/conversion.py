"""Convert single I3-files to SQLite database using a temporary directory."""

import sys
import os

# 1. 定义你的私有环境路径
my_env_path = "/data/user/jliao/envs/mlarson_graphnet_env/lib/python3.12/site-packages"

# 2. 如果路径已在列表中，先删掉它，再把它塞到绝对的第一位 (Index 0)
if my_env_path in sys.path:
    sys.path.remove(my_env_path)
sys.path.insert(0, my_env_path)

# 3. 🔥 核心核武：如果内存里已经缓存了 numpy，强行把它踢出去！
if 'numpy' in sys.modules:
    del sys.modules['numpy']

# 4. 现在重新导入，Python 将被迫去你的 Index 0 路径找全新的 1.26.4
import numpy

# --- 验证输出 ---
print(f"Internal Check - NumPy Location: {numpy.__file__}")
print(f"Internal Check - NumPy Version: {numpy.__version__}")







import tempfile
from typing import List
from graphnet.data.extractors import (
    I3TruthExtractor,
    I3FeatureExtractorIceCube86,
)
from graphnet.data.sqlite import SQLiteDataConverter

def main_icecube86(input_i3_dir: str,
                   outdir: str,
                   database_name: str,
                   gcd_rescue: str,
                   workers: int) -> None:
    """Convert a single IceCube-86 I3 file to SQLite format."""
    extractors = [I3TruthExtractor(),
                  I3FeatureExtractorIceCube86('SplitRTCleanedInIcePulses')]
                  
    converter = SQLiteDataConverter(extractors = extractors, 
                                    outdir = outdir,
                                    gcd_rescue = gcd_rescue,
                                    workers = workers)
                                    
    # 传入包含软链接的临时文件夹
    converter(input_i3_dir)
    
    converter.merge_files(os.path.join(outdir, database_name), 
                          max_table_size=400000000)

if __name__ == "__main__":
    if len(sys.argv) != 4:
        print("Usage: python3 conversion.py <gcd_file_path> <i3_file_path> <output_directory>")
        sys.exit(1)

    gcd_path = sys.argv[1]
    i3_path = sys.argv[2]
    out_directory = sys.argv[3]
    
    base_name = os.path.basename(i3_path)
    db_name = base_name.split('.i3')[0]
    
    print("="*50)
    print("GraphNeT Conversion Job Started")
    print("="*50)
    print(f"Target Database Name : {db_name}")
    print(f"Input I3 File        : {i3_path}")
    print(f"Input GCD File       : {gcd_path}")
    print(f"Output Directory     : {out_directory}")
    print("="*50, flush=True) 
    
    os.makedirs(out_directory, exist_ok=True)
    num_workers = 1 
    
    # 核心修复：创建一个临时文件夹，并在其中为 i3 文件创建软链接
    with tempfile.TemporaryDirectory() as tmp_dir:
        print(f"Created temporary directory: {tmp_dir}", flush=True)
        symlink_path = os.path.join(tmp_dir, base_name)
        
        # 创建软链接 (0耗时，不占空间)
        os.symlink(i3_path, symlink_path)
        print(f"Created symlink for i3 file inside temp directory.", flush=True)
        
        # 将这个临时文件夹传递给主函数
        main_icecube86(input_i3_dir = tmp_dir,
                       outdir = out_directory,
                       database_name = db_name,
                       workers = num_workers,
                       gcd_rescue = gcd_path)
                       
    # 退出 with 代码块时，tempfile 会自动销毁临时文件夹和软链接
    
    print("\nConversion successfully completed for:", db_name)
