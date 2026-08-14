#!/usr/bin/env bash
set -euo pipefail

# User guide: docs/madison_condor_quickstart.md

# Reproduce the Madison/HTCondor reconstruction environment used by the
# validated Energy, Track/Cascade, and Direction/Vertex models.
#
# Conversion intentionally uses a different IceTray/Python 3.12 environment.
# micromamba itself, its package cache, and the created environment are not
# tracked in Git.

# IceCube CVMFS setup contaminates micromamba Python through these variables.
# Clear them before invoking micromamba, not only before reconstruction.
unset PYTHONHOME
unset PYTHONPATH

MAMBA="${MAMBA:-/data/user/${USER}/software/micromamba/bin/micromamba}"
MAMBA_ROOT_PREFIX="${MAMBA_ROOT_PREFIX:-/data/user/${USER}/envs/micromamba}"
ENV_NAME="${ENV_NAME:-graphnet-reco}"
ENV_PREFIX="${ENV_PREFIX:-${MAMBA_ROOT_PREFIX}/envs/${ENV_NAME}}"

export MAMBA_ROOT_PREFIX

if [ ! -x "$MAMBA" ]; then
    echo "micromamba is not executable: $MAMBA" >&2
    exit 1
fi

"$MAMBA" create -p "$ENV_PREFIX" -c conda-forge \
    python=3.8.19 \
    pip \
    "icu=78.*" \
    "libgcc-ng=15.*" \
    "libstdcxx-ng=15.*" \
    -y

# The environment C++ runtime must take precedence before Python starts.
# This prevents Madison workers from loading the older /lib64/libstdc++.so.6.
export LD_LIBRARY_PATH="${ENV_PREFIX}/lib:${LD_LIBRARY_PATH:-}"

"$MAMBA" run -p "$ENV_PREFIX" python -m pip install \
    torch==2.2.0 \
    --index-url https://download.pytorch.org/whl/cu118

"$MAMBA" run -p "$ENV_PREFIX" python -m pip install \
    dill==0.3.8 \
    awkward==1.10.5 \
    colorlog==6.8.2 \
    ConfigUpdater==3.2 \
    h5py==3.11.0 \
    matplotlib==3.7.5 \
    numpy==1.24.4 \
    pandas==2.0.3 \
    polars-lts-cpu==0.20.21 \
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

"$MAMBA" run -p "$ENV_PREFIX" python -m pip install \
    torch_cluster==1.6.3+pt22cu118 \
    torch_scatter==2.1.2+pt22cu118 \
    torch_sparse==0.6.18+pt22cu118 \
    -f https://data.pyg.org/whl/torch-2.2.0+cu118.html

"$MAMBA" run -p "$ENV_PREFIX" python -m pip install \
    torch_geometric==2.5.2

LIBSTDCXX="${ENV_PREFIX}/lib/libstdc++.so.6"
if [ ! -e "$LIBSTDCXX" ]; then
    echo "Missing environment C++ runtime: $LIBSTDCXX" >&2
    exit 1
fi
if ! strings "$LIBSTDCXX" | grep "CXXABI_1.3.15" >/dev/null; then
    echo "$LIBSTDCXX does not provide CXXABI_1.3.15" >&2
    exit 1
fi

"$MAMBA" run -p "$ENV_PREFIX" python -c '
import sys
from importlib.metadata import version

import dill
import polars
import torch
import torch_cluster
import torch_geometric
import torch_scatter
import torch_sparse
print("python:", sys.version)
print("torch:", torch.__version__)
print("cuda built:", torch.version.cuda)
print("dill:", dill.__version__)
print("polars-lts-cpu:", version("polars-lts-cpu"))
print("polars module:", polars.__file__)
print("torch_geometric:", torch_geometric.__version__)
print("torch_cluster:", torch_cluster.__version__)
print("torch_scatter:", torch_scatter.__version__)
print("torch_sparse:", torch_sparse.__version__)
'

printf "Environment prefix: %s\n" "$ENV_PREFIX"
