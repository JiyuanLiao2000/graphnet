"""Example of Batch Prediction Model with Test Valve."""

import os
import glob
from typing import Any, Dict, List, Optional

import pandas as pd
import sqlite3
import numpy as np

import torch
from graphnet.constants import EXAMPLE_DATA_DIR, EXAMPLE_OUTPUT_DIR
from graphnet.data.constants import FEATURES, TRUTH
from graphnet.models import StandardModel
from graphnet.models.detector.icecube import IceCube86
from graphnet.models.gnn import DynEdgeTITO
from graphnet.models.graphs import KNNGraph
from graphnet.models.graphs.nodes import NodesAsPulses
from graphnet.models.task.reconstruction import JointPositionandDirectionReco
from graphnet.training.labels import Direction, JointLabel
from graphnet.training.callbacks import ProgressBar
from graphnet.training.loss_functions import VonMisesFisher3DLoss, JointLoss, EuclideanDistanceLoss
from graphnet.utilities.argparse import ArgumentParser
from graphnet.utilities.logging import Logger
from graphnet.data.datamodule import GraphNeTDataModulecustom
from graphnet.data.dataset.sqlite.sqlite_dataset import SQLiteDataset
from graphnet.models import Model   

# Constants (保持原样，与你之前的物理特征完全一致)
features = FEATURES.ICECUBE86
truth = TRUTH.ICECUBE86
truth.append("oneweight")
truth.append("RunID")
truth.append("EventID")
truth.append("SubrunID")
truth.append("SubEventID")

def main(
    input_dir: str,
    output_dir: str,
    pulsemap: str,
    target: str,
    truth_table: str,
    gpus: Optional[List[int]],
    batch_size: int,
    num_workers: int,
    max_files: int,  # 🚰 新增的测试阀参数
) -> None:
    
    logger = Logger()
    logger.info(f"features: {features}")
    logger.info(f"truth: {truth}")

    # 1. 静态配置与图定义 (维持不变)
    config: Dict[str, Any] = {
        "pulsemap": pulsemap,
        "batch_size": batch_size,
        "num_workers": num_workers,
        "target": target,
    }

    graph_definition = KNNGraph(
        detector=IceCube86(),
        node_definition=NodesAsPulses(),
        nb_nearest_neighbours=8,
        input_feature_names=features,
    )
   
    # 2. [重资产移出] 加载模型到 GPU (一次性动作，避免在循环中重复加载)
    model_path = "/storage/home/hcoda1/4/jliao74/r-itaboada3-0/jliao74/VertexReco/Vertex/LargeTC0.04_LRNEW/Iit1/my_numu_database_part_1 (1)/dynedgeTITO_direction_example/model.pth"
    logger.info("Loading model to GPU...")
    model = Model.load(model_path)
    model.eval()

    additional_attributes = [
        "zenith", "azimuth", "position_x", "position_y", "position_z",
        "event_no", "energy", "pid", "interaction_type", "oneweight",
        "RunID", "SubrunID", "EventID", "SubEventID",
    ]
    prediction_columns = [
         "pos_x_pred", "pos_y_pred", "pos_z_pred",
         "dir_x_pred", "dir_y_pred", "dir_z_pred", "dir_kappa_pred",
    ]

    os.makedirs(output_dir, exist_ok=True)

    # 3. 动态获取所有待处理的 .db 文件
    db_files = glob.glob(os.path.join(input_dir, "*.db"))
    db_files.sort() # 排序确保每次测试抓到的都是固定的前几个文件
    
    logger.info(f"Found {len(db_files)} databases in total.")

    # --- 🚰 测试阀逻辑 ---
    if max_files > 0:
        db_files = db_files[:max_files]
        logger.info(f"🚰 TEST VALVE ACTIVE: Limiting processing to {len(db_files)} databases.")
    else:
        logger.info(f"🌊 FULL RUN ACTIVE: Processing all {len(db_files)} databases.")

    # 4. [核心循环] 遍历每个 .db 文件
    for db_path in db_files:
        db_name = os.path.basename(db_path).replace(".db", "")
        output_csv = os.path.join(output_dir, f"{db_name}_DV.csv")

        # 智能断点续传：如果已经存在结果，跳过
        if os.path.exists(output_csv):
            logger.info(f"Skipping {db_name}, already processed.")
            continue
            
        logger.info(f"Processing: {db_name}")

        # --- [聪明的手段] 瞬间提取所有的 event_no ---
        try:
            with sqlite3.connect(db_path) as conn:
                # 绕过庞大的 CSV 列表，直接从数据库内部榨取 event_no 列表
                all_events = pd.read_sql(f"SELECT event_no FROM {truth_table}", conn)["event_no"].tolist()
        except Exception as e:
            logger.error(f"Failed to read {db_path}: {e}")
            continue

        if not all_events:
            logger.warning(f"No events found in {db_name}. Skipping.")
            continue

        # --- 维持原样，安全骗过 DataModule ---
        data_module = GraphNeTDataModulecustom(
            dataset_reference=SQLiteDataset,
            dataset_args={
                "truth_table": truth_table,
                "pulsemaps": config["pulsemap"],
                "truth": truth,
                "features": features,
                "path": [db_path],  # 每次只喂当前的 db
                "graph_definition": graph_definition
            },
            train_dataloader_kwargs={
                "batch_size": config["batch_size"],
                "num_workers": config["num_workers"],
            },
            # 伪造一个极小的训练集应付检查，将全量事件推入验证集用于预测
            train_selections=[all_events[:2]], 
            val_selections=[all_events],
            test_selection=[None],
            labels={
                "joint_labels": JointLabel(
                    azimuth_key="azimuth", zenith_key="zenith",
                    position_keys=("position_x", "position_y", "position_z"),
                    key="joint_labels"
                )
            },
            train_val_split=[0.2, 0.8], # 已被显式 selections 覆盖，安全失效
        )

        validation_dataloader = data_module.val_dataloader

        # 5. 执行极速预测
        try:
            results = model.predict_as_dataframe(
                validation_dataloader,
                additional_attributes=additional_attributes,
                prediction_columns=prediction_columns,
                gpus=gpus,
            )
            # 6. 保存同名 CSV
            results.to_csv(output_csv, index=False)
            logger.info(f"Successfully saved {output_csv}")
        except Exception as e:
            logger.error(f"Prediction failed for {db_name}: {e}")

if __name__ == "__main__":
    parser = ArgumentParser(description="Batch Inference with GraphNeT")

    # 替换了原来的硬编码单文件路径
    parser.add_argument("--input-dir", required=True, help="Directory containing .db files")
    parser.add_argument("--output-dir", required=True, help="Directory to save .csv results")
    parser.add_argument("--pulsemap", default="SRTInIcePulses")
    parser.add_argument("--target", default="direction")
    parser.add_argument("--truth-table", default="truth")
    
    # 🚰 注册测试阀参数：默认 -1 为全量运行
    parser.add_argument("--max-files", type=int, default=-1, help="Test valve: max number of .db files to process.")

    parser.with_standard_arguments(
        ("gpus", [0]),
        ("batch-size", 100),
        "num-workers",
    )
    args, unknown = parser.parse_known_args()

    main(
        args.input_dir,
        args.output_dir,
        args.pulsemap,
        args.target,
        args.truth_table,
        args.gpus,
        args.batch_size,
        args.num_workers,
        args.max_files, # 传递给 main
    )
