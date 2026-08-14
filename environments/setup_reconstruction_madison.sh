#!/usr/bin/env bash
set -euo pipefail

# Reproduce the Madison/HTCondor reconstruction environment used by the
# validated Energy, Track/Cascade, and Direction/Vertex models.
#
# micromamba itself is intentionally not tracked in Git. Install it separately
# and point MAMBA at the executable before running this script if needed.

MAMBA="${MAMBA:-/data/user/jliao/software/micromamba/bin/micromamba}"
MAMBA_ROOT_PREFIX="${MAMBA_ROOT_PREFIX:-/data/user/jliao/envs/micromamba}"
ENV_NAME="${ENV_NAME:-graphnet-reco}"

export MAMBA_ROOT_PREFIX

"$MAMBA" create -n "$ENV_NAME" -c conda-forge python=3.8.19 pip -y

"$MAMBA" run -n "$ENV_NAME" python -m pip install \
    torch==2.2.0 \
    --index-url https://download.pytorch.org/whl/cu118

"$MAMBA" run -n "$ENV_NAME" python -m pip install \
    dill==0.3.8 \
    awkward==1.10.5 \
    colorlog==6.8.2 \
    ConfigUpdater==3.2 \
    h5py==3.11.0 \
    matplotlib==3.7.5 \
    numpy==1.24.4 \
    pandas==2.0.3 \
    polars==0.20.21 \
    pyarrow==15.0.2 \
    pydantic==2.7.0 \
    pytorch-lightning==2.2.2 \
    scikit-learn==1.3.2 \
    scipy==1.10.1 \
    SQLAlchemy==2.0.29 \
    timer==0.2.2 \
    torchmetrics==1.3.2 \
    tqdm==4.66.2 \
    wandb==0.16.6 \
    lightning-utilities==0.11.2 \
    ruamel.yaml==0.18.6

"$MAMBA" run -n "$ENV_NAME" python -m pip install \
    torch_cluster==1.6.3+pt22cu118 \
    torch_scatter==2.1.2+pt22cu118 \
    torch_sparse==0.6.18+pt22cu118 \
    -f https://data.pyg.org/whl/torch-2.2.0+cu118.html

"$MAMBA" run -n "$ENV_NAME" python -m pip install \
    torch_geometric==2.5.2

"$MAMBA" run -n "$ENV_NAME" python -c '
import sys, dill, torch, torch_geometric, torch_cluster, torch_scatter, torch_sparse
print("python:", sys.version)
print("torch:", torch.__version__)
print("cuda built:", torch.version.cuda)
print("dill:", dill.__version__)
print("torch_geometric:", torch_geometric.__version__)
print("torch_cluster:", torch_cluster.__version__)
print("torch_scatter:", torch_scatter.__version__)
print("torch_sparse:", torch_sparse.__version__)
'
