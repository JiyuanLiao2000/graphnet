"""Example of Batch Prediction Model for Energy with Test Valve."""

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
from graphnet.models.detector.icecube import IceCubeDeepCore # ⚠️ 注意：这里是 DeepCore
from graphnet.models.gnn import DynEdge, DynEdgeTITO
from graphnet.models.graphs import KNNGraph
from graphnet.models.graphs.nodes import NodesAsPulses
from graphnet.utilities.argparse import ArgumentParser
from graphnet.utilities.logging import Logger
from graphnet.data.datamodule import GraphNeTDataModulecustom
from graphnet.data.dataset.sqlite.sqlite_dataset import SQLiteDataset
from graphnet.models import Model

features = FEATURES.ICECUBE86
truth = TRUTH.ICECUBE86
truth.extend(["oneweight", "RunID", "EventID", "SubrunID", "SubEventID"])

def main(
    input_dir: str,
    output_dir: str,
    model_path: str,
    pulsemap: str,
    target: str,
    truth_table: str,
    gpus: Optional[List[int]],
    batch_size: int,
    num_workers: int,
    max_files: int,  # 🚰 测试阀
) -> None:

    logger = Logger()
    logger.info(f"features: {features}")
    logger.info(f"truth: {truth}")

    config: Dict[str, Any] = {
        "pulsemap": pulsemap,
        "batch_size": batch_size,
        "num_workers": num_workers,
        "target": target,
    }

    # ⚠️ 确保使用 DeepCore
    graph_definition = KNNGraph(
        detector=IceCubeDeepCore(),
        node_definition=NodesAsPulses(),
        nb_nearest_neighbours=8,
        input_feature_names=features,
    )

    # Load Energy model
    logger.info(f"Loading Energy model: {model_path}")
    model = Model.load(model_path)

    # ⚠️ 你的特殊补丁
    if not hasattr(model.backbone, '_skip_readout'):
        model.backbone._skip_readout = False

    model.eval()

    additional_attributes = [
        "event_no",
        "energy",
        "pid",
        "interaction_type",
        "oneweight",
        "RunID",
        "SubrunID",
        "EventID",
        "SubEventID",
    ]

    os.makedirs(output_dir, exist_ok=True)

    db_files = glob.glob(os.path.join(input_dir, "*.db"))
    db_files.sort()

    logger.info(f"Found {len(db_files)} databases in total.")

    # --- 🚰 测试阀逻辑 ---
    if max_files > 0:
        db_files = db_files[:max_files]
        logger.info(f"🚰 TEST VALVE ACTIVE: Limiting processing to {len(db_files)} databases.")
    else:
        logger.info(f"🌊 FULL RUN ACTIVE: Processing all {len(db_files)} databases.")

    for db_path in db_files:
        db_name = os.path.basename(db_path).replace(".db", "")
        output_csv = os.path.join(output_dir, f"{db_name}_E.csv") # 🏷️ 命名后缀为 EV.csv

        if os.path.exists(output_csv):
            logger.info(f"Skipping {db_name}, already processed.")
            continue

        logger.info(f"Processing: {db_name}")

        try:
            with sqlite3.connect(db_path) as conn:
                all_events = pd.read_sql(f"SELECT event_no FROM {truth_table}", conn)["event_no"].tolist()
        except Exception as e:
            logger.error(f"Failed to read {db_path}: {e}")
            continue

        if not all_events:
            logger.warning(f"No events found in {db_name}. Skipping.")
            continue

        data_module = GraphNeTDataModulecustom(
            dataset_reference=SQLiteDataset,
            dataset_args={
                "truth_table": truth_table,
                "pulsemaps": config["pulsemap"],
                "truth": truth,
                "features": features,
                "path": [db_path],
                "graph_definition": graph_definition
            },
            train_dataloader_kwargs={
                "batch_size": config["batch_size"],
                "num_workers": config["num_workers"],
            },
            train_selections=[all_events[:2]],
            val_selections=[all_events],
            test_selection=[None],
            train_val_split=[0.2, 0.8],
        )

        validation_dataloader = data_module.val_dataloader

        try:
            # ⚠️ 这里没有传入 prediction_columns，保持与你原代码一致
            results = model.predict_as_dataframe(
                validation_dataloader,
                additional_attributes=additional_attributes,
                gpus=gpus,
            )
            results.to_csv(output_csv, index=False)
            logger.info(f"Successfully saved {output_csv}")
        except Exception as e:
            logger.error(f"Prediction failed for {db_name}: {e}")

if __name__ == "__main__":
    parser = ArgumentParser(description="Batch Energy Inference with GraphNeT")

    parser.add_argument("--input-dir", required=True)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--model-path", required=True)
    parser.add_argument("--pulsemap", default="SRTInIcePulses") # 默认值，可以在sbatch里覆盖
    parser.add_argument("--target", default="energy")
    parser.add_argument("--truth-table", default="truth")
    parser.add_argument("--max-files", type=int, default=-1)

    parser.with_standard_arguments(
        ("gpus", [0]),
        ("batch-size", 100),
        "num-workers",
    )
    args, unknown = parser.parse_known_args()

    main(
        args.input_dir,
        args.output_dir,
        args.model_path,
        args.pulsemap,
        args.target,
        args.truth_table,
        args.gpus,
        args.batch_size,
        args.num_workers,
        args.max_files,
    )
