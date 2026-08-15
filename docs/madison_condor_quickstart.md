# Madison HTCondor End-to-End Quickstart

This is the supported onboarding path for the complete Madison workflow:

```text
IceCube I3 + matching GCD
    -> GraphNeT SQLite
    -> Energy reconstruction
    -> Track/Cascade reconstruction
    -> Direction/Vertex reconstruction
```

The conversion and reconstruction stages deliberately use different
environments. Conversion uses the complete shared Madison IceTray/Python 3.12
runtime validated by this repository. Reconstruction uses a user-owned,
Git-reproducible micromamba Python 3.8 / PyTorch 2.2 environment.

A user who already has GraphNeT SQLite databases may skip the
[conversion phase](#conversion-phase-i3--gcd---sqlite) and continue at
[Install micromamba](#2-install-micromamba-without-modifying-bashrc).

No Singularity image or container is required.

## What the workflow produces

Each manifest row produces one SQLite database. The three independent
reconstruction jobs then produce:

| Stage | Model | Output |
| --- | --- | --- |
| I3/GCD conversion | none | one GraphNeT `.db` per I3 file |
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
- one or more IceCube I3 files and the matching GCD path for each file, or
  existing GraphNeT SQLite databases;
- the pulse series to extract, commonly `SplitRTCleanedInIcePulses` or
  `SRTInIcePulses`.

GCD/I3 matching is dataset-specific. Complete that matching before submission
and record it as the two-column manifest described below.

Start in a clean Bash shell. Do not source IceCube CVMFS manually in the shell
that will later configure reconstruction. The conversion preflight and Condor
wrapper source CVMFS inside their own processes, while reconstruction wrappers
clear IceCube environment variables before Python starts.

## 1. Clone `main` to shared storage

```bash
export REPO="/data/user/$USER/software/graphnet_unified"

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

## Dependency and installation contract

Cloning the repository supplies the GraphNeT source used by this workflow. Do
not install the repository as a Python package into either Madison runtime. The
conversion preflight and all reconstruction wrappers set `PYTHONPATH` to
`$REPO/src`, so the checked-out custom classes and import paths are used
directly.

The authoritative dependency entry points are:

| Scope | Authoritative files/runtime | Status |
| --- | --- | --- |
| Madison conversion | `environments/check_conversion_madison.sh` plus the complete shared IceTray/Python 3.12 overlay | Validated as one runtime |
| Madison reconstruction | `environments/setup_reconstruction_madison.sh` and `environments/reconstruction-madison.yml` | Git-reproducible and validated |
| Generic GraphNeT packaging | `setup.py`, `requirements/torch_*.txt`, and the generic Install section in `README.md` | Not a Madison deployment entry point |

For the Madison workflow, do **not** run any of the following:

```bash
pip install .
pip install -e .
pip install -e '.[torch]'
pip install -r requirements/torch_gpu.txt -e '.[develop,torch]'
```

Those generic package constraints are intentionally broader than the validated
Condor contract. Resolving them again can replace the tested Torch/PyG pair,
install a non-legacy-compatible Polars wheel, or change dependencies such as
Awkward. A single `setup.py` also cannot describe both the IceTray/Python 3.12
conversion runtime and the Python 3.8/CUDA reconstruction runtime.

If you need a separate, general-purpose GraphNeT development installation,
create a third environment and follow the generic installation documentation
there. Never reuse or modify either validated Madison runtime for that purpose.

## Conversion phase: I3 + GCD -> SQLite

The user-facing submission layer reuses the exact validated conversion baseline:

- `workflows/conversion/exe.sh`
- `workflows/conversion/conversion.py`

Those files retain the working Madison IceTray and Python paths. The
parameterized submit file under `workflows/conversion/condor/` supplies
user-specific storage paths without changing the baseline.

### A. Validate the complete shared conversion runtime

Run the tracked preflight from the repository root:

```bash
cd "$REPO"
bash environments/check_conversion_madison.sh
```

The default shared runtime is:

```text
IceCube CVMFS: /cvmfs/icecube.opensciencegrid.org/py3-v4.4.2/setup.sh
IceTray:       /data/user/mlarson/icetray/build/env-shell.sh
Python:        /data/user/jliao/envs/mlarson_graphnet_env/bin/python3
site-packages: /data/user/jliao/envs/mlarson_graphnet_env/lib/python3.12/site-packages
```

Every path component was verified as readable/executable by ordinary Madison
users. The Python executable resolves to the CVMFS Python 3.12.5 installation;
the user path supplies the complete, validated site-packages overlay. Treat the
overlay as one runtime rather than removing packages that may be implicit
dependencies.

A successful check ends with:

```text
Conversion runtime preflight: PASS
converter: I3ToSQLiteConverter
extractors: I3TruthExtractor I3FeatureExtractorIceCube86
```

The script supports `CVMFS_SETUP`, `ICETRAY_ENV_SHELL`,
`CONVERSION_PYTHON`, and `CONVERSION_SITE_PACKAGES` overrides if the
Madison shared deployment moves.

### B. Prepare the conversion submit directory

```bash
export CONVERSION_SUBMIT_DIR="/scratch/$USER/graphnet-conversion"
export CONVERSION_OUTPUT_DIR="/data/user/$USER/graphnet_workflow/sqlite"
export PULSEMAP="SplitRTCleanedInIcePulses"

mkdir -p "$CONVERSION_SUBMIT_DIR"

cp "$REPO/workflows/conversion/exe.sh" \
   "$REPO/workflows/conversion/conversion.py" \
   "$REPO/workflows/conversion/condor/conversion.sub" \
   "$CONVERSION_SUBMIT_DIR/"

cd "$CONVERSION_SUBMIT_DIR"
```

The generic submit file invokes `/bin/bash exe.sh`, so the copied baseline
script does not need an executable file mode. Logs stay in the submitter-local
scratch directory. Final databases are written to shared
`/data/user/$USER/graphnet_workflow/sqlite`.

The defaults assume the checkout path used in section 1. For a different
checkout, output directory, or pulse series, override the corresponding submit
macros with `condor_submit -append`.

### C. Create the GCD/I3 manifest

Create `manifest.txt` with exactly two whitespace-separated paths per row:

```text
/shared/gcd/GCD_Run001.i3.gz /shared/i3/Run001.i3.zst
/shared/gcd/GCD_Run002.i3.gz /shared/i3/Run002.i3.zst
```

The first column is the GCD; the second is the I3 file. GCD `.tar`,
`.tar.gz`, and `.tgz` archives are supported. Paths containing whitespace
are not supported by this manifest format.

One manifest row queues one Condor process and produces one database named from
the I3 basename.

### D. Parse the job before submitting

```bash
condor_submit -dump conversion.ad conversion.sub

grep -E '^(Cmd|Args|RequestCpus|RequestMemory|TransferInput|Out|Err|UserLog)' \
  conversion.ad
```

Expected fields include:

```text
Cmd="/bin/bash"
Args="exe.sh <GCD> <I3> <output> <pulsemap> <GraphNeT root>"
RequestCpus=1
RequestMemory=8192
TransferInput="exe.sh,conversion.py"
```

`-dump` writes the resolved ClassAd locally and does not submit to the
schedd. Its synthetic “submitted to cluster 1” message is not a live cluster.

### E. Submit and monitor conversion

```bash
condor_submit \
  -batch-name graphnet-conversion \
  conversion.sub

condor_q
```

The submit file requires workers with the IceCube CVMFS mount, transfers the
two baseline scripts into the execute sandbox, and propagates conversion
failures as nonzero job exit codes.

After completion:

```bash
ls -lh conversion.*.log conversion.*.out conversion.*.err
find "$CONVERSION_OUTPUT_DIR" -maxdepth 1 -type f -name '*.db' -print
```

The Condor event log must report normal termination with return value 0.

### F. Validate the converted SQLite databases

```bash
export INPUT_DIR="$CONVERSION_OUTPUT_DIR"

/usr/bin/python3 - "$INPUT_DIR" "$PULSEMAP" <<'PY'
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
        truth_events = connection.execute(
            "SELECT COUNT(DISTINCT event_no) FROM truth"
        ).fetchone()[0]
        pulse_events = connection.execute(
            f"SELECT COUNT(DISTINCT event_no) FROM {pulsemap}"
        ).fetchone()[0]
        pulse_rows = connection.execute(
            f"SELECT COUNT(*) FROM {pulsemap}"
        ).fetchone()[0]

    if truth_events != pulse_events:
        raise SystemExit(
            f"{database}: truth events={truth_events}, "
            f"pulse events={pulse_events}"
        )
    print(
        f"PASS: {database}: events={truth_events}, "
        f"pulse rows={pulse_rows}"
    )

print("SQLite validation: PASS")
PY
```

The validated end-to-end smoke produced 443 truth events, 443 pulse-table
events, and 15,077 pulse rows. Continue only after the new databases pass this
check.

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

If you completed the conversion phase, `INPUT_DIR` already points to
`$CONVERSION_OUTPUT_DIR` and `PULSEMAP` already records the extracted pulse
series. Confirm them:

```bash
printf 'INPUT_DIR=%s\nPULSEMAP=%s\n' "$INPUT_DIR" "$PULSEMAP"
```

If you skipped conversion because databases already exist, set both variables
now:

```bash
export INPUT_DIR="/data/user/$USER/path/to/sqlite"
export PULSEMAP="SplitRTCleanedInIcePulses"
```

Then discover the direct database children:

```bash
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
export OUTPUT_BASE="/data/user/$USER/graphnet_workflow/reconstruction"

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
| Conversion preflight reports an unreadable shared path | Madison shared runtime moved or permissions changed | Use the documented path override only after the replacement runtime is verified |
| Conversion exits without a database | I3/GCD, pulse series, IceTray, or converter failure | Read the conversion `.err`, `.out`, and final Condor event-log entry |
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

## Environment boundary

Conversion and reconstruction intentionally remain separate:

| Stage | Runtime |
| --- | --- |
| I3/GCD -> SQLite | shared IceTray + CVMFS Python 3.12 runtime |
| SQLite -> Energy/TC/DV | user-owned micromamba Python 3.8 + PyTorch 2.2/cu118 |

Do not run IceCube CVMFS setup inside reconstruction jobs. Do not try to load
the serialized reconstruction models in the Python 3.12 conversion runtime.
The reconstruction wrappers clear `PYTHONHOME` and `PYTHONPATH` and select
the environment C++ runtime before Python starts.

See `workflows/conversion/README.md` for the conversion operational reference.

## Key files

| Purpose | File |
| --- | --- |
| Shared conversion runtime preflight | `environments/check_conversion_madison.sh` |
| Parameterized conversion submit file | `workflows/conversion/condor/conversion.sub` |
| GCD/I3 manifest example | `workflows/conversion/condor/manifest.example` |
| Validated conversion baseline | `workflows/conversion/exe.sh`, `conversion.py` |
| Reconstruction environment installer | `environments/setup_reconstruction_madison.sh` |
| Reconstruction dependency mirror | `environments/reconstruction-madison.yml` |
| Condor operational reference | `workflows/reconstruction/condor/README.md` |
| Energy entry point | `workflows/reconstruction/energy.py` |
| Track/Cascade entry point | `workflows/reconstruction/track_cascade.py` |
| Direction/Vertex entry point | `workflows/reconstruction/direction_vertex.py` |
| Model contracts and checksums | `models/MODELS.md` |
| Architecture and validation record | `docs/unified_workflow.md` |

Reference scripts under `workflows/**/reference/` are preserved historical
inputs. They are not the active deployment entry points and should not be
edited for normal production use.

