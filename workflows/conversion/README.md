Exit code: 0
Wall time: 0.5 seconds
Output:
# Madison HTCondor I3-to-SQLite conversion

This directory contains the active Madison conversion workflow:

- `conversion.py`
- `exe.sh`
- `condor.sub`

Each Condor process converts one I3 file plus its matching GCD into one
GraphNeT SQLite database. The pulse table name is a parameter.

## Important portability boundary

The current conversion workflow is validated on Madison, but it is not a
generic installation recipe. It intentionally depends on a site-specific
IceCube Python 3.12 stack:

- IceCube CVMFS `py3-v4.4.2` setup;
- an IceTray `env-shell` path;
- a private Python executable;
- a private Python `site-packages` path used by `conversion.py`.

Those private paths are not committed as software artifacts and may not be
readable by another user. A new user must obtain or build an equivalent
IceTray/GraphNeT conversion environment and update the active workflow paths
before submitting. The micromamba Python 3.8 reconstruction environment is not
a replacement for this conversion environment.

If SQLite databases already exist, skip this directory and follow
`docs/madison_condor_quickstart.md`.

## Inputs

The conversion CLI is:

```text
conversion.py <gcd_file_path> <i3_file_path> <output_directory> <pulse_key>
```

GCD/I3 matching is deliberately outside the converter. Generate a two-column,
whitespace-separated manifest with one job per row:

```text
/shared/path/GCD_Run001.i3.gz /shared/path/Run001.i3.zst
/shared/path/GCD_Run002.i3.gz /shared/path/Run002.i3.zst
```

GCD tar archives are supported by `exe.sh`; it extracts the first matching
`*.i3*` file into a job-local temporary directory.

Common pulse keys include:

- `SplitRTCleanedInIcePulses`
- `SRTInIcePulses`

Use the pulse key actually present in the source I3 files. Reconstruction must
later use the same table name.

## Paths that must be reviewed

Before submission, review all of the following:

### `condor.sub`

- `pulse_key`
- `graphnet_root`
- shared SQLite output directory in `arguments`
- `/scratch/$USER/...` log, stdout, and stderr paths
- manifest filename in the `queue ... from ...` line

### `exe.sh`

- IceCube CVMFS setup version
- IceTray `env-shell.sh` path
- private Python executable path

### `conversion.py`

- private Python `site-packages` path (`my_env_path`)

Do not submit the tracked file unchanged under another account: its default
paths are the validated author's smoke/deployment paths.

## Storage and Condor behavior

- Submit and log files belong under submitter-local `/scratch/$USER/...`.
- The repository, input I3/GCD, and final SQLite databases must be on storage
  visible to execute workers, such as `/data/user/...` or experiment storage.
- `should_transfer_files = YES` transfers `conversion.py` and captures job
  output correctly.
- Conversion failures propagate through `exe.sh` as a nonzero Condor exit
  code.

One successful job produces one `.db` named from the I3 basename. No database
merge step is performed by this workflow.

## Environment separation

Do not source or reuse the conversion CVMFS environment for reconstruction.
IceCube setup exports `PYTHONHOME` and `PYTHONPATH`, which can break the
micromamba reconstruction Python. The reconstruction wrappers clear these
variables and use the separate environment documented in
`docs/madison_condor_quickstart.md`.

## Active and reference files

Use the files directly under `workflows/conversion/` for deployment. Files
under `workflows/conversion/reference/condor/` preserve the original reference
workflow and should not be modified.

