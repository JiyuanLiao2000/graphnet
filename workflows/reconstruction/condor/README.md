# Madison HTCondor reconstruction

These files run Energy, Track/Cascade, and Direction/Vertex reconstruction
from GraphNeT SQLite databases on Madison GPU workers.

**New users should start with the complete
[`docs/madison_condor_quickstart.md`](../../../docs/madison_condor_quickstart.md).**
This README is the shorter operational reference for the files in this
directory.

Conversion uses a separate IceTray/Python 3.12 environment. Do not source the
IceCube CVMFS setup in reconstruction jobs.

## Files

| Workflow | Wrapper | Submit file | Default memory |
| --- | --- | --- | --- |
| Energy | `energy.sh` | `energy.sub` | 8 GB |
| Track/Cascade | `track_cascade.sh` | `track_cascade.sub` | 12 GB |
| Direction/Vertex | `direction_vertex.sh` | `direction_vertex.sub` | 12 GB |

The wrapper is transferred into the execute sandbox. Python entry points,
models, the micromamba environment, input databases, and output directories
remain on worker-visible shared storage.

## Do not submit the templates unchanged

The tracked `.sub` files preserve the original validated smoke-test paths under
`/data/user/jliao/...`. Every user must override or edit these macros:

| Macro | Meaning |
| --- | --- |
| `input_dir` | Shared directory containing direct `*.db` children |
| `output_dir` | Shared, writable directory for final CSV files |
| `model_path` | Workflow-specific tracked `.pth` file |
| `pulsemap` | Pulse table that exists in every input database |
| `graphnet_root` | Shared checkout of this repository |
| `env_prefix` | Created micromamba environment prefix |
| `mamba` | Executable micromamba binary |
| `num_workers` | Positive DataLoader worker count |
| `batch_size` | Positive inference batch size |
| `max_files` | `1` for a smoke test or `-1` for all discovered databases |

Prefer `condor_submit -append` so the Git-tracked templates remain unchanged.
For example:

```bash
condor_submit energy.sub \
  -append "input_dir = $INPUT_DIR" \
  -append "output_dir = $OUTPUT_DIR" \
  -append "model_path = $REPO/models/energy/energy_model.pth" \
  -append "pulsemap = $PULSEMAP" \
  -append "graphnet_root = $REPO" \
  -append "env_prefix = $ENV_PREFIX" \
  -append "mamba = $MAMBA" \
  -append "num_workers = 4" \
  -append "batch_size = 10" \
  -append "max_files = 1" \
  -append "request_memory = 12GB"
```

The Quickstart provides complete commands for all three workflows.

## Storage contract

- Submit files and Condor logs: submitter-local `/scratch/$USER/...`
- Runtime sandbox: `$_CONDOR_SCRATCH_DIR`
- Repository, environment, databases, models, and final CSV:
  worker-visible shared `/data/user/$USER/...`

Madison prohibits writing Condor logs directly under `/data/user`. Workers
must not be expected to see the submitter's `/scratch` path.

## Resources

Every reconstruction job requests one GPU with:

```text
gpus_minimum_capability = 6.1
gpus_minimum_memory = 6GB
```

This excludes GTX 980 GPUs while allowing validated GTX 1080 and A40 workers.

The CPU accounting rule is:

```text
request_cpus = num_workers
```

`num_workers` must be at least one because this GraphNeT DataLoader configures
`prefetch_factor`. The four-worker / four-CPU / 12 GB profile passed all three
workflows. Test resource changes on one database before scaling up.

## Runtime isolation

Each wrapper performs these steps before Python starts:

1. Clears `PYTHONHOME` and `PYTHONPATH` inherited from IceCube software.
2. Adds `/usr/bin:/bin` to `PATH` so `micromamba run` can locate a shell.
3. Prepends `${ENV_PREFIX}/lib` to `LD_LIBRARY_PATH` so the environment
   `libstdc++` provides `CXXABI_1.3.15`.
4. Sets `PYTHONPATH` to the checked-out repository's `src` directory.
5. Runs micromamba by explicit prefix without activation or `.bashrc` changes.

Use the tracked wrappers. Reimplementing these exports in an ad-hoc submit
script commonly reintroduces the Python contamination or C++ ABI failures that
the deployment layer is designed to prevent.

## Legacy CPU compatibility

Some Madison GPU workers are `x86_64-v2` systems without AVX2. The standard
Polars 0.20.21 wheel can terminate with `SIGILL` / exit code 132 on these
workers. The environment therefore pins `polars-lts-cpu==0.20.21`, which still
imports as `polars`.

Do not use `POLARS_SKIP_CPU_CHECK`, and do not add an AVX2 requirement to normal
production jobs. The compatibility package is intended to keep the workflow
portable across the heterogeneous pool.

To deliberately test a legacy CPU only, add this option to the complete
Quickstart submission command:

```text
-append 'requirements = (TARGET.has_avx2 =!= true)'
```

That constraint is diagnostic and must not be copied into production submit
files.

## Validated outputs

Using pulsemap `SplitRTCleanedInIcePulses`, the Madison smoke database produced
all three CSV outputs successfully:

- Energy: `_E.csv`
- Track/Cascade: `TC.csv`
- Direction/Vertex: `_DV.csv`

The Track/Cascade prediction column is currently called `target_pred`. The
name is a known non-blocking issue; prediction values were validated.

## Troubleshooting

The Quickstart contains the full symptom/cause/action table. The first checks
for any failed job are:

```bash
condor_q
condor_q -better-analyze <cluster.proc>
ls -lh *.log *.out *.err
```

Do not treat warnings about `icecube` being unavailable as reconstruction
failures when the input is SQLite. Always use the Condor event log's final exit
code and the existence/content of the expected CSV as the success criteria.

