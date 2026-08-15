# Unified IceCube GraphNeT Workflow

## Goal

Maintain one GraphNeT codebase and one reproducible workflow for the complete
Madison/HTCondor reconstruction chain:

```text
GCD + I3
   |
   v
GraphNeT conversion
   |
   v
SQLite database
   |
   +--> Track/cascade reconstruction
   |
   +--> Energy reconstruction
   |
   +--> Direction/vertex reconstruction
```

PACE is the reconstruction regression environment. Madison/HTCondor is the
deployment target for the complete workflow.

New users should start with `docs/madison_condor_quickstart.md`. It provides
the supported clean-checkout path from I3/GCD conversion through SQLite
validation, reconstruction-environment creation, all three GPU jobs, output
verification, and troubleshooting.

## GraphNeT baseline

The unified repository is based on GraphNeT commit
`6d578d651e38710c5858524b6abee602d3bd2ed6`. This baseline contains the custom
reconstruction components required by the existing trained models.

## Madison conversion integration

The PACE GraphNeT baseline includes two Madison conversion components.

### I3Reader

File: `src/graphnet/data/readers/i3reader.py`

The reader skips frames when `pop_physics()` raises an exception, preventing
subsequent processing from using an invalid or stale frame.

### I3TruthExtractor

File: `src/graphnet/data/extractors/icecube/i3truthextractor.py`

The following Madison truth fields are preserved:

- `oneweight`
- `true_length`
- `reconstructed_length`
- `reconstructed_energy`
- `deltallh`

The Madison elasticity behavior is also preserved.

## Conversion workflow

The validated baseline files are:

- `workflows/conversion/conversion.py`
- `workflows/conversion/exe.sh`
- `workflows/conversion/condor.sub`

They remain unchanged as the regression baseline. Ordinary users submit the
same `exe.sh` and `conversion.py` through the parameterized layer:

- `workflows/conversion/condor/conversion.sub`

The original Madison reference files remain preserved under
`workflows/conversion/reference/condor/`.

Each Condor job follows this structure:

```text
one Condor job
    -> one I3 file
    -> one SQLite database
```

`I3ToSQLiteConverter` derives the SQLite filename from the I3 basename, so
this single-file workflow does not require a merge operation.

The pulse series is configurable and passes through the following files:

```text
workflows/conversion/condor/conversion.sub
    -> baseline exe.sh
    -> baseline conversion.py
```

Example pulse series are `SplitRTCleanedInIcePulses` and
`SRTInIcePulses`.

GCD/I3 matching remains external to the core workflow. A manifest may provide
one `(GCD path, I3 path)` pair per Condor job.

## Madison conversion environment

Conversion and reconstruction intentionally use separate environments.

The complete shared conversion runtime includes:

- `/cvmfs/icecube.opensciencegrid.org/py3-v4.4.2/setup.sh`
- `/data/user/mlarson/icetray/build/env-shell.sh`
- `/data/user/jliao/envs/mlarson_graphnet_env/bin/python3`
- `/data/user/jliao/envs/mlarson_graphnet_env/lib/python3.12/site-packages`

The Python executable resolves to CVMFS Python 3.12.5. Permission checks
confirmed that ordinary Madison users can read and execute every component.
The full site-packages overlay remains intact so implicit conversion
dependencies are not removed.

`environments/check_conversion_madison.sh` validates the shared runtime,
current checkout, NumPy, IceCube, converter, and extractors without
contaminating the caller's shell. The unified checkout is supplied through
`PYTHONPATH` and points to the current repository's `src` directory.

The original Madison conversion smoke and the later parameterized user-path
smoke both produced `Greco_0414_Run00142433.db`. The later database contained
443 matching truth/pulse events and 15,077 pulse rows before passing all three
reconstruction workflows.

## Reconstruction workflows

The cross-environment reconstruction entry points are:

- `workflows/reconstruction/energy.py`
- `workflows/reconstruction/track_cascade.py`
- `workflows/reconstruction/direction_vertex.py`

The original PACE-tested scripts are preserved under
`workflows/reconstruction/reference/pace/`. The active PACE regression
wrappers are under `workflows/reconstruction/pace/`.

### Energy

- Model: `models/energy/energy_model.pth`
- Detector preprocessing: `IceCubeDeepCore`
- PACE regression smoke test: passed
- Madison interactive GPU reconstruction smoke test: passed

In this GraphNeT version, `IceCubeDeepCore` and `IceCube86` are not
interchangeable. The trained energy model contains an `IceCubeDeepCore`
detector, and this preprocessing contract must be preserved.

### Track/cascade

- Model: `models/track_cascade/track_cascade_model.pth`
- Detector preprocessing: `IceCube86`
- PACE regression smoke test: passed
- Madison model deserialization test: passed

Known non-blocking issue: the `target_pred` CSV column should eventually be
renamed to `track_score`. Prediction values are unaffected.

### Direction/vertex

- Model: `models/direction_vertex/direction_vertex_model.pth`
- Detector preprocessing: `IceCube86`
- PACE regression smoke test: passed
- Madison model deserialization test: passed

The trained model depends on these custom GraphNeT components:

- `JointPositionandDirectionReco`
- `JointLabel`
- `JointLoss`

The prediction contract is:

- `position_x`
- `position_y`
- `position_z`
- `dir_x`
- `dir_y`
- `dir_z`
- `direction_kappa`

The training target contains six values:

- `position_x`
- `position_y`
- `position_z`
- `dir_x`
- `dir_y`
- `dir_z`

`JointLoss` combines the position and direction losses according to the
current implementation:

```text
combined_loss = alpha * position_loss + direction_loss
```

## Madison reconstruction environment

The existing Madison conversion environment uses Python 3.12 and cannot load
the current serialized reconstruction models because of Python/pickle typing
compatibility. Reconstruction therefore uses a separate micromamba environment.

The validated core versions are:

```text
Python 3.8.19
torch 2.2.0+cu118
CUDA build 11.8
dill 0.3.8
pytorch-lightning 2.2.2
torch-geometric 2.5.2
torch-cluster 1.6.3+pt22cu118
torch-scatter 2.1.2+pt22cu118
torch-sparse 0.6.18+pt22cu118
```

The complete tested dependency installation is recorded in
`environments/setup_reconstruction_madison.sh`. The declarative mirror in
`environments/reconstruction-madison.yml` records the full pinned Python
dependency set and the CUDA 11.8 PyTorch/PyG wheel sources. It also requests the
environment ICU and GCC 15 runtime packages needed to provide the validated
`libstdc++.so.6.0.35` compatibility layer.

The setup script is the canonical Madison installation path because it preserves
the tested package-install order and verifies that the resulting C++ runtime
exports `CXXABI_1.3.15`. It clears IceCube Python variables before invoking
micromamba and creates/runs the environment by its explicit filesystem prefix,
so neither shell activation nor `.bashrc` modification is required.

`micromamba` itself, its package cache, the created environment directory, and
runtime `.so` files are deployment dependencies and must not be committed to
Git.

The three Energy, Track/Cascade, and Direction/Vertex `.pth` models all load
successfully in this environment, including the custom Direction/Vertex
classes.

### Environment isolation

IceCube CVMFS setup exports `PYTHONHOME` and `PYTHONPATH`. Those variables must
not leak into the reconstruction environment. Reconstruction wrappers must
start by clearing them before launching the micromamba Python environment.

On Madison GPU workers the micromamba environment also needs its own C++ runtime
to take precedence over `/lib64/libstdc++.so.6`. The tested environment
contains `libstdc++.so.6.0.35`, which provides `CXXABI_1.3.15`. Reconstruction
wrappers therefore prepend the environment library directory:

```bash
unset PYTHONHOME
unset PYTHONPATH
export LD_LIBRARY_PATH="${ENV_PREFIX}/lib:${LD_LIBRARY_PATH:-}"
export PYTHONPATH="${GRAPHNET_ROOT}/src"
```

This resolved the observed SQLite/ICU startup failure caused by the system
`libstdc++` being too old for the environment's ICU library.

HTCondor may also start a job with a minimal `PATH`. `micromamba run` locates
`bash` or `sh` through `PATH` when it builds its activation wrapper. The
reconstruction wrapper therefore prepends `/usr/bin:/bin` before invoking
micromamba. Without this setting, libmamba can emit
`Failed to find a shell to run the script with` even though its fallback may
allow the payload to continue.

### Legacy CPU compatibility

The Madison GPU pool includes `x86_64-v2` workers whose ClassAds do not
advertise `has_avx2`. On these workers, importing the standard
`polars==0.20.21` wheel can terminate Python with `SIGILL` (exit code
132) because that wheel expects AVX2, FMA, BMI1, BMI2, and LZCNT instructions. The reconstruction
environment therefore pins:

```text
polars-lts-cpu==0.20.21
```

This compatibility distribution exposes the same `polars` Python module and
version. It was verified by importing Polars from a clean environment and by
completing Energy inference in a non-interactive Condor job deliberately
scheduled on a worker without AVX2. Skipping Polars' CPU check is not a safe
substitute because it does not make unsupported machine instructions valid.

The production submit files intentionally do not exclude legacy CPUs. For a
targeted compatibility test only, the constraint can be added at submission
time:

```condor
requirements = (TARGET.has_avx2 =!= true)
```

This temporary constraint must not be copied into the normal production submit
files.

## Madison HTCondor GPU behavior

The Madison GPU pool currently includes GTX 980, GTX 1080, and A40 nodes. The
validated smoke test requested one GPU with:

```text
request_gpus = 1
gpus_minimum_capability = 6.1
gpus_minimum_memory = 6GB
```

This excludes the 3.9 GB GTX 980 nodes while allowing GTX 1080 and A40 nodes.
The interactive test landed on a GTX 1080 and verified:

- `CUDA_VISIBLE_DEVICES` was assigned by HTCondor
- PyTorch saw exactly one GPU
- `torch.cuda.is_available()` returned `True`
- a real CUDA tensor computation completed successfully

Condor submit/log files are kept under submitter-local `/scratch`. GPU workers
must not be expected to see that same `/scratch` path. Jobs therefore use
Condor file transfer for stdout/stderr and use shared `/data/user/...` paths
for repository, environment, SQLite input, and final reconstruction outputs.

For Madison/HTCondor reconstruction, the project convention is a strict
one-to-one request:

```text
request_cpus = num_workers
```

`num_workers` must be a positive integer. The validated Energy smoke test uses
`num_workers=1`, so its Condor job requests one CPU. `num_workers=0` is not
valid for this GraphNeT DataLoader because its configured `prefetch_factor`
requires multiprocessing. The Condor wrapper rejects zero before starting
Python so the failure is immediate and explicit.

The validated Track/Cascade and Direction/Vertex batch tests were submitted
concurrently as independent jobs. Each job used `num_workers=4`,
`request_cpus=4`, and `request_memory=12GB`, with separate Condor logs and
shared output directories. The later clean-environment Energy test used the
same four-worker, four-CPU, 12 GB profile on a legacy CPU worker. These tests
exercised production-like data loading while preserving the one-to-one
CPU-worker accounting rule.

All three submit files expose `batch_size` and `max_files` macros. The tracked
smoke configuration uses `batch_size=10` and `max_files=1`; set
`max_files=-1` to process every database discovered in the input directory.
Operational submission instructions are in
`workflows/reconstruction/condor/README.md`.

## Reconstruction model verification

See `models/MODELS.md`. The three deployment models are tracked with SHA256
checksums.

## Current validation status

All three unified reconstruction workflows passed PACE validation with the same
SQLite database, `Greco_0610_Run00142709.db`.

Madison validation stands at:

| Workflow / component | Status |
| --- | --- |
| Shared conversion runtime access and import preflight | Passed |
| Parameterized user-facing conversion submit layer | Passed |
| I3 + GCD -> SQLite in a non-interactive Condor job | Passed |
| Converted SQLite truth/pulse event consistency | Passed |
| Reconstruction micromamba environment recreation from Git | Passed |
| Condor GPU allocation and CUDA computation | Passed |
| Energy, Track/Cascade, and Direction/Vertex model loads | Passed |
| Energy reconstruction in a non-interactive Condor GPU job | Passed |
| Track/Cascade reconstruction in a non-interactive Condor GPU job | Passed |
| Direction/Vertex reconstruction in a non-interactive Condor GPU job | Passed |
| Clean-environment Energy inference on a legacy CPU worker | Passed |

## End-to-end user-path validation

The user-facing workflow was repeated from the repository branch on Madison on
2026-08-14/15 using the parameterized conversion submit layer and the clean
reconstruction environment.

Conversion cluster `29550249` processed:

```text
GCD:
  /data/exp/IceCube/2026/internal-system/sps-gcd/0414/
  PFGCD_Run00142433_Subrun00000000.flat.tar

I3:
  /data/user/mlarson/icetray/scripts/upgrade_lid/output/
  Greco_0414_Run00142433.i3.zst
```

The resulting database passed:

```text
truth:                     443 rows, 443 events
SplitRTCleanedInIcePulses: 15077 rows, 443 events
```

That newly generated database was then used directly by three concurrent
non-interactive GPU jobs:

| Workflow | Cluster | Result |
| --- | ---: | --- |
| Energy | `29550452` | Passed |
| Track/Cascade | `29550453` | Passed |
| Direction/Vertex | `29550456` | Passed |

All three produced the expected CSV files without changing the baseline
conversion scripts or the reconstruction entry points.

## Completion status

The complete Madison/HTCondor user path has passed:

```text
clean checkout
    -> shared conversion runtime preflight
    -> parameterized I3/GCD conversion
    -> SQLite schema/event validation
    -> Git-recreated reconstruction environment
    -> Energy / TC / DV Condor GPU jobs
    -> validated CSV outputs
```

The two-environment boundary remains intentional. Conversion uses the complete
shared Madison IceTray/Python 3.12 runtime. Reconstruction uses the user-owned,
Git-managed micromamba Python 3.8 / PyTorch 2.2 + CUDA 11.8 environment.

Operational onboarding is maintained in
`docs/madison_condor_quickstart.md`.
