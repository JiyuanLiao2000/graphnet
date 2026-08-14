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

PACE is the current development and reconstruction regression environment.
Madison/HTCondor is the deployment target for the complete workflow.

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

## Madison environment

The Madison compatibility layer is preserved for the initial deployment test:

- CVMFS IceCube setup
- IceTray `env-shell`
- private GraphNeT Python environment
- private Python site-packages and NumPy handling

These components have supported Madison conversions and should not be removed
or simplified before Condor validation.

The reference environment includes:

- `/cvmfs/icecube.opensciencegrid.org/py3-v4.4.2/setup.sh`
- `/data/user/mlarson/icetray/build/env-shell.sh`
- `/data/user/jliao/envs/mlarson_graphnet_env/bin/python3`

The existing Madison `PYTHONPATH` points to the previous custom GraphNeT
checkout. During deployment, it must point to the `src` directory of the
unified Git checkout under test.

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

In this GraphNeT version, `IceCubeDeepCore` and `IceCube86` are not
interchangeable. The trained energy model contains an `IceCubeDeepCore`
detector, and this preprocessing contract must be preserved.

### Track/cascade

- Model: `models/track_cascade/track_cascade_model.pth`
- Detector preprocessing: `IceCube86`
- PACE regression smoke test: passed

Known non-blocking issue: the `target_pred` CSV column should eventually be
renamed to `track_score`. Prediction values are unaffected.

### Direction/vertex

- Model: `models/direction_vertex/direction_vertex_model.pth`
- Detector preprocessing: `IceCube86`
- PACE regression smoke test: passed

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

## Reconstruction model verification

See `models/MODELS.md`. The three deployment models are tracked with SHA256
checksums.

## Current validation status

All three unified reconstruction workflows passed PACE validation with the same
SQLite database, `Greco_0610_Run00142709.db`.

| Workflow | Status |
| --- | --- |
| Energy | Passed |
| Track/cascade | Passed |
| Direction/vertex | Passed |

Each workflow produced the expected CSV reconstruction output with reasonable
values.

## Next milestone

The next milestone is Madison/HTCondor validation from a fixed repository
commit:

1. Commit and push the unified integration branch.
2. Clone or check out the exact commit on Madison.
3. Point the Madison `PYTHONPATH` to that checkout's `src` directory.
4. Preserve the existing IceTray, CVMFS, and private Python environment.
5. Run a GCD and I3 conversion.
6. Verify the resulting SQLite schema and event counts.
7. Run energy, track/cascade, and direction/vertex reconstruction on Condor.
8. Compare the Condor outputs with the validated PACE behavior.

The migration is complete only after this chain runs successfully on
Madison/HTCondor:

```text
I3 -> SQLite -> Energy / TC / DV
```

