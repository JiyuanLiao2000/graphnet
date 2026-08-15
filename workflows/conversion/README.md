# Madison HTCondor I3-to-SQLite conversion

This directory contains the validated Madison conversion stage for the complete
workflow:

```text
IceCube I3 + matching GCD
    -> GraphNeT SQLite
    -> Energy / Track-Cascade / Direction-Vertex
```

New users should follow the complete
`docs/madison_condor_quickstart.md`. This README is the operational reference
for the conversion files.

## Validated baseline and user-facing layer

The three files directly under `workflows/conversion/` are the successful
Madison baseline:

- `conversion.py`
- `exe.sh`
- `condor.sub`

The baseline contains the original site and deployment paths and remains
unchanged as a regression reference.

Ordinary users submit through:

- `workflows/conversion/condor/conversion.sub`
- `workflows/conversion/condor/manifest.example`

The parameterized submit file reuses the exact baseline `exe.sh` and
`conversion.py`. It replaces user-specific repository, output, log, and
manifest handling without reimplementing the converter.

Files under `workflows/conversion/reference/condor/` preserve the earlier
reference workflow and must not be modified.

## Shared Madison conversion runtime

Conversion uses this complete validated runtime:

```text
IceCube CVMFS setup:
  /cvmfs/icecube.opensciencegrid.org/py3-v4.4.2/setup.sh

IceTray env-shell:
  /data/user/mlarson/icetray/build/env-shell.sh

Python:
  /data/user/jliao/envs/mlarson_graphnet_env/bin/python3

Python site-packages:
  /data/user/jliao/envs/mlarson_graphnet_env/lib/python3.12/site-packages
```

The Python executable resolves to CVMFS Python 3.12.5. The user-owned path
provides the full working site-packages overlay. Permission checks confirmed
that ordinary Madison users can traverse, read, and execute every component.

Treat the overlay as one validated runtime. Do not remove packages merely
because they appear unrelated; imports may have implicit dependencies. This
shared runtime is the default compatibility backend, so new users do not need
to compile IceTray or reconstruct the conversion environment before their
first job.

If the shared deployment moves, the environment preflight supports explicit
path overrides. The baseline files themselves should remain unchanged until a
replacement runtime has passed the same end-to-end regression.

## Preflight

From the repository root:

```bash
bash environments/check_conversion_madison.sh
```

The script checks:

- the CVMFS setup;
- the shared IceTray `env-shell`;
- the complete Python 3.12 overlay;
- the current repository's GraphNeT source;
- NumPy;
- `I3ToSQLiteConverter`;
- `I3TruthExtractor`;
- `I3FeatureExtractorIceCube86`.

A successful result contains:

```text
Conversion runtime preflight: PASS
```

The script runs CVMFS setup inside its own process and does not contaminate the
caller's shell.

Optional overrides are:

```text
CVMFS_SETUP
ICETRAY_ENV_SHELL
CONVERSION_PYTHON
CONVERSION_SITE_PACKAGES
GRAPHNET_ROOT
```

## Inputs and manifest

The conversion CLI implemented by the baseline is:

```text
conversion.py <gcd_file_path> <i3_file_path> <output_directory> <pulse_key>
```

GCD/I3 matching is dataset-specific and deliberately remains outside the core
converter. Copy `workflows/conversion/condor/manifest.example` as a starting
point or create a two-column, whitespace-separated manifest:

```text
/shared/path/GCD_Run001.i3.gz /shared/path/Run001.i3.zst
/shared/path/GCD_Run002.i3.gz /shared/path/Run002.i3.zst
```

The first column is the matching GCD; the second is the I3 file. Paths
containing whitespace are not supported. One row queues one Condor process.

GCD `.tar`, `.tar.gz`, and `.tgz` archives are supported. `exe.sh`
extracts the first matching `*.i3*` member into a job-local temporary
directory.

Common pulse keys include:

- `SplitRTCleanedInIcePulses`
- `SRTInIcePulses`

Reconstruction must use the same pulse table written during conversion.

## Prepare a submission

The standard checkout and output layout is:

```text
/data/user/$USER/software/graphnet_unified
/data/user/$USER/graphnet_workflow/sqlite
/scratch/$USER/graphnet-conversion
```

Prepare the submit directory:

```bash
export REPO="/data/user/$USER/software/graphnet_unified"
export CONVERSION_SUBMIT_DIR="/scratch/$USER/graphnet-conversion"

mkdir -p "$CONVERSION_SUBMIT_DIR"

cp "$REPO/workflows/conversion/exe.sh" \
   "$REPO/workflows/conversion/conversion.py" \
   "$REPO/workflows/conversion/condor/conversion.sub" \
   "$CONVERSION_SUBMIT_DIR/"

cd "$CONVERSION_SUBMIT_DIR"
```

Create `manifest.txt`, then parse the resolved ClassAd without submitting:

```bash
condor_submit -dump conversion.ad conversion.sub
```

The generic submit file uses:

```text
Cmd=/bin/bash
Args=exe.sh <GCD> <I3> <output> <pulsemap> <GraphNeT root>
RequestCpus=1
RequestMemory=8 GB
```

It transfers both baseline scripts. Calling `/bin/bash exe.sh` avoids a
dependency on the copied script's executable file mode.

The custom manifest macro is called `input_manifest`; `manifest` is a
reserved HTCondor boolean keyword and must not be reused.

## Submit

For the standard layout and default
`SplitRTCleanedInIcePulses` pulse series:

```bash
condor_submit \
  -batch-name graphnet-conversion \
  conversion.sub
```

For a nonstandard checkout or output path, override the macros without editing
the tracked template:

```bash
condor_submit conversion.sub \
  -append "graphnet_root = /shared/path/graphnet" \
  -append "output_dir = /shared/path/sqlite" \
  -append "pulse_key = SRTInIcePulses" \
  -append "input_manifest = another_manifest.txt"
```

## Storage and Condor behavior

- Submit files and Condor logs belong under submitter-local
  `/scratch/$USER/...`.
- The repository, I3/GCD inputs, and final SQLite databases must be visible to
  execute workers.
- The generic default writes databases under
  `/data/user/$USER/graphnet_workflow/sqlite`.
- `should_transfer_files = YES` sends `exe.sh` and `conversion.py` to the
  execute sandbox.
- Conversion failures propagate as nonzero Condor exit codes.
- One successful process produces one `.db` named from the I3 basename.
- No database merge step is performed.

## Validate before reconstruction

Every new database must contain both `truth` and the selected pulse table.
Their distinct `event_no` counts should agree.

The end-to-end validation converted one test I3 file and produced:

```text
truth:                       443 events
SplitRTCleanedInIcePulses:   443 events, 15077 rows
```

Use the complete SQLite validation command in
`docs/madison_condor_quickstart.md` before launching reconstruction.

## Environment separation

Do not reuse or source the conversion environment for reconstruction.
Conversion uses IceTray and Python 3.12. Reconstruction uses the separate
Git-managed micromamba Python 3.8 / PyTorch 2.2 + CUDA 11.8 environment.

IceCube setup exports `PYTHONHOME` and `PYTHONPATH`, which can break the
micromamba Python. The tracked reconstruction wrappers clear those variables
and select the environment C++ runtime before starting Python.
