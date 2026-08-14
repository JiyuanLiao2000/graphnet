# Madison HTCondor reconstruction

These files run GraphNeT reconstruction from SQLite databases on Madison GPU
workers. Conversion uses a separate IceTray/Python 3.12 environment; do not
source the IceCube CVMFS setup in reconstruction jobs.

## Files

- `energy.sh` and `energy.sub`
- `track_cascade.sh` and `track_cascade.sub`
- `direction_vertex.sh` and `direction_vertex.sub`

The wrappers share the validated environment-isolation, C++ runtime, shell
`PATH`, GPU, file-transfer, and shared-storage contract.

## Storage contract

- Submit files and Condor logs: submitter-local `/scratch/<user>/...`
- Runtime sandbox: `$_CONDOR_SCRATCH_DIR`
- Repository, micromamba environment, input databases, models, and final CSV:
  worker-visible shared `/data/user/<user>/...`

Madison prohibits writing Condor logs directly under `/data/user`. Workers
must not be expected to see the submitter's `/scratch` path.

## Prepare a submission

Pull the desired Git revision, copy the relevant `.sh` and `.sub` pair to a
directory under `/scratch`, and submit from that directory. Edit the path
macros near the top of each submit file for the target checkout, environment,
model, input directory, and shared output directory.

The tracked files are one-database smoke configurations:

```text
batch_size = 10
max_files = 1
```

Set `max_files = -1` to process all databases found in `input_dir`.

## Resources

Every reconstruction job requests one GPU with:

```text
gpus_minimum_capability = 6.1
gpus_minimum_memory = 6GB
```

The required accounting rule is:

```text
request_cpus = num_workers
```

`num_workers` must be at least one because this GraphNeT DataLoader configures
`prefetch_factor`. Energy was validated with one worker. Track/Cascade and
Direction/Vertex were validated concurrently with four workers, four requested
CPUs, and 12 GB of requested memory per job.

## Runtime isolation

Each wrapper performs these steps before Python starts:

1. Clears `PYTHONHOME` and `PYTHONPATH` inherited from IceCube software.
2. Adds `/usr/bin:/bin` to `PATH` so `micromamba run` can locate a shell.
3. Prepends `${ENV_PREFIX}/lib` to `LD_LIBRARY_PATH` so the environment
   `libstdc++` provides `CXXABI_1.3.15`.
4. Sets `PYTHONPATH` to the checked-out repository's `src` directory.
5. Runs micromamba by the explicit environment prefix without shell activation
   or `.bashrc` changes.

## Validated outputs

Using pulsemap `SplitRTCleanedInIcePulses`, the Madison smoke database produced
Energy, Track/Cascade, and Direction/Vertex CSV files successfully. The scripts
use the suffixes `_E.csv`, `TC.csv`, and `_DV.csv`, respectively.
