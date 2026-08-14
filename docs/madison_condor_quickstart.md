# Madison HTCondor Reconstruction Quickstart

This is the supported onboarding path for running the repository's Energy,
Track/Cascade, and Direction/Vertex reconstruction workflows on the Madison
HTCondor GPU pool.

The guide starts from one or more GraphNeT SQLite databases. If the input is
still IceCube I3 + GCD, read [Conversion from I3](#conversion-from-i3) before
continuing.

No Singularity image, container, IceTray setup, or shell activation is needed
for SQLite reconstruction.

## What the workflow produces

For each input database, the three independent jobs produce:

| Workflow | Model | Output suffix |
| --- | --- | --- |
| Energy | `models/energy/energy_model.pth` | `_E.csv` |
| Track/Cascade | `models/track_cascade/track_cascade_model.pth` | `TC.csv` |
| Direction/Vertex | `models/direction_vertex/direction_vertex_model.pth` | `_DV.csv` |

The Energy model requires `IceCubeDeepCore` preprocessing. Track/Cascade and
Direction/Vertex require `IceCube86`. These contracts are already encoded in
the tracked Python entry points and must not be changed.

## Storage layout

Madison uses three different storage locations:

| Location | Purpose |
| --- | --- |
| `/data/user/$USER/...` | Repository, micromamba, environment, input databases, models, final CSV files |
| `/scratch/$USER/...` | Condor submit files and logs on `npx-submitter` |
| `$_CONDOR_SCRATCH_DIR` | Execute-side sandbox created by HTCondor |

Do not put Condor log paths under `/data/user`. Do not assume a GPU worker can
see the submitter's `/scratch` directory. The tracked jobs transfer wrappers
and stdout/stderr while writing final CSV files directly to shared
`/data/user` storage.

## Before starting

You need:

- a Madison account and access to `npx-submitter`;
- writable `/data/user/$USER` and `/scratch/$USER` directories;
- `git`, `curl`, and `tar` on the submit host;
- one or more GraphNeT SQLite `.db` files directly inside one input directory;
- the pulse table name used during conversion, commonly
  `SplitRTCleanedInIcePulses` or `SRTInIcePulses`.

Start in a clean Bash shell. Do **not** source the IceCube CVMFS setup for
reconstruction.

## 1. Clone `main` to shared storage

```bash
export REPO="/data/user/$USER/software/graphnet"

git clone --branch main --single-branch \
  https://github.com/JiyuanLiao2000/graphnet.git "$REPO"

cd "$REPO"
git status -sb
```

For an existing checkout:

```bash
cd "$REPO"
git switch main
git pull --ff-only
```

The repository must be under shared storage such as `/data/user`; GPU workers
cannot use a checkout located only under submitter-local `/scratch`.

## 2. Install micromamba without modifying `.bashrc`

The validated deployment used micromamba 2.9.0. Micromamba is a standalone
binary and is not committed to this repository. The command below downloads
the current official Linux x86-64 build. For an exact reproduction, obtain the
2.9.0 build from the official micromamba releases instead.

```bash
export MAMBA_DIR="/data/user/$USER/software/micromamba"
export MAMBA="$MAMBA_DIR/bin/micromamba"

if [ ! -x "$MAMBA" ]; then
  mkdir -p "$MAMBA_DIR"
  cd "$MAMBA_DIR"
  curl -Ls https://micro.mamba.pm/api/micromamba/linux-64/latest \
    | tar -xvj bin/micromamba
fi

"$MAMBA" --version
```

Official installation documentation:
<https://mamba.readthedocs.io/en/stable/installation/micromamba-installation.html>

Do not run `micromamba shell init`. The workflow uses explicit paths and
`micromamba run`, so no shell activation or `.bashrc` change is required.

## 3. Create the reconstruction environment

```bash
export MAMBA_ROOT_PREFIX="/data/user/$USER/envs/micromamba"
export ENV_NAME="graphnet-reco"
export ENV_PREFIX="$MAMBA_ROOT_PREFIX/envs/$ENV_NAME"

cd "$REPO"
MAMBA="$MAMBA" \
MAMBA_ROOT_PREFIX="$MAMBA_ROOT_PREFIX" \
ENV_NAME="$ENV_NAME" \
ENV_PREFIX="$ENV_PREFIX" \
bash environments/setup_reconstruction_madison.sh
```

The script creates the tested Python 3.8 / PyTorch 2.2 + CUDA 11.8 environment,
installs the matching PyG wheels, verifies `CXXABI_1.3.15`, and checks the
legacy-compatible Polars installation.

The final output should include values equivalent to:

```text
python: 3.8.19
torch: 2.2.0+cu118
cuda built: 11.8
dill: 0.3.8
polars-lts-cpu: 0.20.21
torch_geometric: 2.5.2
```

Do not replace `polars-lts-cpu` with standard `polars`. Some Madison GPU
workers are legacy `x86_64-v2` systems, and the standard wheel can terminate
with `SIGILL` / exit code 132.

## 4. Verify the models

```bash
cd "$REPO"
sha256sum \
  models/energy/energy_model.pth \
  models/track_cascade/track_cascade_model.pth \
  models/direction_vertex/direction_vertex_model.pth
```

Expected SHA256 values:

```text
c64b0d882cd0e025780e1b414831b1e94de06185560cbf9d693e16798a118b6a
1322fd213801f680b61045c72557440239356f2e21329879011d210d666193ad
88db3f74d0399ddf13a303b9b74dbe5ca3c68f101ed5cf607c5f037ad1f8f54c
```

A recommended preflight loads all three serialized models before requesting a
GPU slot:

```bash
unset PYTHONHOME
unset PYTHONPATH
export PATH="/usr/bin:/bin:${PATH:-}"
export LD_LIBRARY_PATH="$ENV_PREFIX/lib:${LD_LIBRARY_PATH:-}"
export PYTHONPATH="$REPO/src"

"$MAMBA" run -p "$ENV_PREFIX" python - \
  "$REPO/models/energy/energy_model.pth" \
  "$REPO/models/track_cascade/track_cascade_model.pth" \
  "$REPO/models/direction_vertex/direction_vertex_model.pth" <<'PY'
import sys
from graphnet.models import Model

for model_path in sys.argv[1:]:
    model = Model.load(model_path)
    print(f"PASS: {model_path} -> {type(model).__name__}")
PY
```

This also verifies that the repository's custom Direction/Vertex classes are
available at the import paths required by the pickle.

See `models/MODELS.md` for the mapping between files, workflows, and detector
preprocessing.

## 5. Check the SQLite input

Set the input directory and pulse table:

```bash
export INPUT_DIR="/data/user/$USER/path/to/sqlite"
export PULSEMAP="SplitRTCleanedInIcePulses"

find "$INPUT_DIR" -maxdepth 1 -type f -name '*.db' -print
```

The reconstruction scripts discover only `.db` files directly inside
`INPUT_DIR`; discovery is not recursive.

This optional check confirms that every database has the required `truth` and
pulse tables:

```bash
python3 - "$INPUT_DIR" "$PULSEMAP" <<'PY'
import glob
import os
import sqlite3
import sys

input_dir, pulsemap = sys.argv[1:]
databases = sorted(glob.glob(os.path.join(input_dir, "*.db")))
if not databases:
    raise SystemExit(f"No .db files found in {input_dir}")

for database in databases:
    with sqlite3.connect(database) as connection:
        tables = {
            row[0]
            for row in connection.execute(
                "SELECT name FROM sqlite_master WHERE type='table'"
            )
        }
    missing = {"truth", pulsemap} - tables
    if missing:
        raise SystemExit(f"{database}: missing tables {sorted(missing)}")
    print(f"PASS: {database}")
PY
```

Use exactly the pulse table present in the databases. A pulsemap mismatch is
not repaired by the reconstruction job.

## 6. Prepare a submit directory

```bash
export SUBMIT_DIR="/scratch/$USER/graphnet-reconstruction"
export OUTPUT_BASE="/data/user/$USER/graphnet-reconstruction-output"

mkdir -p "$SUBMIT_DIR" "$OUTPUT_BASE"
cp "$REPO"/workflows/reconstruction/condor/{energy,track_cascade,direction_vertex}.{sh,sub} \
  "$SUBMIT_DIR"/
cd "$SUBMIT_DIR"
```

The `.sub` files contain the original validated smoke-test paths as examples.
Never submit them unchanged. The commands below override every user-specific
path without editing the tracked templates.

## 7. Choose smoke-test settings

Start with one database before processing a full directory:

```bash
export NUM_WORKERS=4
export BATCH_SIZE=10
export MAX_FILES=1
```

`NUM_WORKERS` must be a positive integer. The submit files enforce:

```text
request_cpus = num_workers
```

The four-worker / four-CPU / 12 GB profile passed Energy, Track/Cascade, and
Direction/Vertex validation. If a workload needs different resources, change
the worker count and memory together and test on one database first.

## 8. Submit Energy

```bash
condor_submit energy.sub \
  -batch-name graphnet-energy \
  -append "input_dir = $INPUT_DIR" \
  -append "output_dir = $OUTPUT_BASE/energy" \
  -append "model_path = $REPO/models/energy/energy_model.pth" \
  -append "pulsemap = $PULSEMAP" \
  -append "graphnet_root = $REPO" \
  -append "env_prefix = $ENV_PREFIX" \
  -append "mamba = $MAMBA" \
  -append "num_workers = $NUM_WORKERS" \
  -append "batch_size = $BATCH_SIZE" \
  -append "max_files = $MAX_FILES" \
  -append "request_memory = 12GB"
```

## 9. Submit Track/Cascade

```bash
condor_submit track_cascade.sub \
  -batch-name graphnet-track-cascade \
  -append "input_dir = $INPUT_DIR" \
  -append "output_dir = $OUTPUT_BASE/track_cascade" \
  -append "model_path = $REPO/models/track_cascade/track_cascade_model.pth" \
  -append "pulsemap = $PULSEMAP" \
  -append "graphnet_root = $REPO" \
  -append "env_prefix = $ENV_PREFIX" \
  -append "mamba = $MAMBA" \
  -append "num_workers = $NUM_WORKERS" \
  -append "batch_size = $BATCH_SIZE" \
  -append "max_files = $MAX_FILES" \
  -append "request_memory = 12GB"
```

## 10. Submit Direction/Vertex

```bash
condor_submit direction_vertex.sub \
  -batch-name graphnet-direction-vertex \
  -append "input_dir = $INPUT_DIR" \
  -append "output_dir = $OUTPUT_BASE/direction_vertex" \
  -append "model_path = $REPO/models/direction_vertex/direction_vertex_model.pth" \
  -append "pulsemap = $PULSEMAP" \
  -append "graphnet_root = $REPO" \
  -append "env_prefix = $ENV_PREFIX" \
  -append "mamba = $MAMBA" \
  -append "num_workers = $NUM_WORKERS" \
  -append "batch_size = $BATCH_SIZE" \
  -append "max_files = $MAX_FILES" \
  -append "request_memory = 12GB"
```

The three jobs are independent and may run concurrently.

The tracked GPU request is:

```text
request_gpus = 1
gpus_minimum_capability = 6.1
gpus_minimum_memory = 6GB
```

This excludes GTX 980 GPUs while allowing the validated GTX 1080 and A40
classes.

## 11. Monitor the jobs

```bash
condor_q
```

For an idle job that is not matching:

```bash
condor_q -better-analyze <cluster.proc>
```

After completion, inspect all three log types:

```bash
ls -lh *.log *.out *.err
```

- `.log` records scheduling, execution host, transfer, and exit status.
- `.out` records the wrapper configuration and GraphNeT progress.
- `.err` contains Python warnings and tracebacks.

A successful Condor event log ends with normal termination and return value 0.
Warnings about `icecube` being unavailable are expected for reconstruction
from SQLite and are not failures.

## 12. Verify the CSV outputs

```bash
find "$OUTPUT_BASE" -maxdepth 2 -type f -name '*.csv' -print
```

Inspect headers and a few rows before scaling up:

```bash
head -n 3 "$OUTPUT_BASE"/energy/*.csv
head -n 3 "$OUTPUT_BASE"/track_cascade/*.csv
head -n 3 "$OUTPUT_BASE"/direction_vertex/*.csv
```

The Track/Cascade prediction column is currently named `target_pred`. This is
a known non-blocking naming issue; the validated prediction values are not
affected.

## 13. Process every database

After the one-file smoke test passes, choose fresh output directories and set:

```bash
export MAX_FILES=-1
```

Repeat the three submit commands. `-1` tells each workflow to process every
`.db` file discovered directly inside `INPUT_DIR`.

Do not run multiple jobs that write the same database/workflow result into the
same output directory. For a large campaign, split databases into separate
input directories or build a manifest-driven layer around these one-directory
entry points.

## Common failures

| Symptom | Cause | Action |
| --- | --- | --- |
| `No module named encodings` | IceCube CVMFS set `PYTHONHOME`/`PYTHONPATH` | Start a clean shell and use the tracked reconstruction wrapper; do not source CVMFS |
| `CXXABI_1.3.15 not found` | Worker loaded `/lib64/libstdc++.so.6` | Use the tracked wrapper and the environment created by the setup script |
| `Failed to find a shell to run the script with` | Minimal worker `PATH` | Use the tracked wrapper, which adds `/usr/bin:/bin` before micromamba |
| `prefetch_factor option could only be specified in multiprocessing` | `num_workers=0` | Set a positive worker count; keep `request_cpus = num_workers` |
| Exit code 132 / `Illegal instruction` during `import polars` | Standard Polars wheel on a legacy CPU | Recreate the environment from `main` and verify `polars-lts-cpu==0.20.21` |
| Logs cannot be written under `/data/user` | Madison Condor log policy | Submit from `/scratch/$USER` and keep final data under `/data/user/$USER` |
| Job remains idle | No currently available slot satisfies CPU, memory, GPU, and machine `START` policies | Use `condor_q <job> -better-analyze`; avoid pinning one host |
| No CSV and nonzero exit code | Reconstruction failed before output | Read `.err`, `.out`, and the final termination entry in `.log` |

Lightning may recommend more workers than the job requested. Do not follow that
generic warning beyond the Condor CPU allocation. Request the intended CPU
count and set `num_workers` to the same value.

Do not work around the Polars failure with `POLARS_SKIP_CPU_CHECK`; skipping a
check cannot add missing CPU instructions.

## Conversion from I3

SQLite reconstruction and I3 conversion intentionally use different Python
environments. The active conversion workflow is under `workflows/conversion/`,
but its IceTray `env-shell`, private Python, and Python site-packages paths are
Madison deployment-specific.

If starting from I3 + GCD, read `workflows/conversion/README.md`. Do not run
IceCube CVMFS setup inside a reconstruction job, and do not try to load the
serialized reconstruction models in the Python 3.12 conversion environment.

## Key files

| Purpose | File |
| --- | --- |
| Environment installer | `environments/setup_reconstruction_madison.sh` |
| Pinned dependency mirror | `environments/reconstruction-madison.yml` |
| Condor operational reference | `workflows/reconstruction/condor/README.md` |
| Energy entry point | `workflows/reconstruction/energy.py` |
| Track/Cascade entry point | `workflows/reconstruction/track_cascade.py` |
| Direction/Vertex entry point | `workflows/reconstruction/direction_vertex.py` |
| Model contracts and checksums | `models/MODELS.md` |
| Architecture and validation record | `docs/unified_workflow.md` |

Reference scripts under `workflows/**/reference/` are preserved historical
inputs. They are not the active deployment entry points and should not be
edited for normal production use.

