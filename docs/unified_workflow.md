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

The active conversion files are:

- `workflows/conversion/conversion.py`
- `workflows/conversion/exe.sh`
- `workflows/conversion/condor.sub`

The original Madison files are preserved under
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
condor.sub
    -> exe.sh
    -> conversion.py
```

Example pulse series are `SplitRTCleanedInIcePulses` and
`SRTInIcePulses`.

GCD/I3 matching remains external to the core workflow. A manifest may provide
one `(GCD path, I3 path)` pair per Condor job.

## Madison conversion environment

Conversion and reconstruction intentionally use separate environments.

The conversion compatibility layer remains:

- CVMFS IceCube setup
- IceTray `env-shell`
- private conversion Python environment
- private Python site-packages and NumPy handling

The reference conversion environment includes:

- `/cvmfs/icecube.opensciencegrid.org/py3-v4.4.2/setup.sh`
- `/data/user/mlarson/icetray/build/env-shell.sh`
- `/data/user/jliao/envs/mlarson_graphnet_env/bin/python3`

The unified checkout is supplied through `PYTHONPATH` and must point to the
current repository's `src` directory.

The Madison conversion smoke test successfully produced
`Greco_0414_Run00142433.db` from an I3 file and its GCD input. The resulting
SQLite schema and event counts were validated.

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
`environments/setup_reconstruction_madison.sh`. `micromamba` itself and the
created environment directory are deployment dependencies and are not tracked
as binaries in Git.

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

The current reconstruction convention is:

```text
request_cpus = num_workers
```

The validated Energy smoke test uses `num_workers=1`. `num_workers=0` is not a
valid default for this GraphNeT DataLoader because its configured
`prefetch_factor` requires multiprocessing.

## Reconstruction model verification

See `models/MODELS.md`. The three deployment models are tracked with SHA256
checksums.

## Current validation status

All three unified reconstruction workflows passed PACE validation with the same
SQLite database, `Greco_0610_Run00142709.db`.

Madison validation currently stands at:

| Workflow / component | Status |
| --- | --- |
| I3 -> SQLite conversion | Passed |
| Reconstruction micromamba environment | Passed |
| Condor GPU allocation | Passed |
| PyTorch CUDA computation | Passed |
| Energy model load | Passed |
| Track/cascade model load | Passed |
| Direction/vertex model load | Passed |
| Energy reconstruction on converted Madison DB | Passed |
| Track/cascade reconstruction on Madison | Pending |
| Direction/vertex reconstruction on Madison | Pending |
| Non-interactive Condor reconstruction wrapper | Pending |

## Next milestone

The next milestone is to convert the validated interactive Energy command into
a non-interactive HTCondor reconstruction wrapper and submit file. After that
wrapper succeeds, reuse the same environment and Condor contract for
Track/Cascade and Direction/Vertex reconstruction.

The migration is complete only after this chain runs successfully on
Madison/HTCondor:

```text
I3 -> SQLite -> Energy / TC / DV
```
