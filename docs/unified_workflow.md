
# Unified IceCube GraphNeT Workflow

## Goal

Maintain one GraphNeT codebase and one reproducible workflow that can run the
full reconstruction chain on Madison / HTCondor:

GCD + I3
   |
   v
GraphNeT conversion
   |
   v
SQLite database
   |
   +--> Track / Cascade reconstruction
   |
   +--> Energy reconstruction
   |
   +--> Direction / Vertex reconstruction


PACE is currently used as the development and reconstruction regression
environment. The deployment target for the complete workflow is Madison /
HTCondor.

GraphNeT baseline

The unified repository is based on GraphNeT commit:

6d578d651e38710c5858524b6abee602d3bd2ed6

This baseline contains the custom reconstruction components required by the
existing trained models.

Madison conversion integration

Two pieces of Madison conversion behavior have been integrated into the PACE
GraphNeT baseline.

I3Reader

File:

src/graphnet/data/readers/i3reader.py

The reader preserves the Madison behavior of skipping problematic
pop_physics() frames instead of allowing non-I3 read exceptions to continue
with an invalid/stale frame.

I3TruthExtractor

File:

src/graphnet/data/extractors/icecube/i3truthextractor.py

The Madison custom truth information has been preserved:

oneweight
true_length
reconstructed_length
reconstructed_energy
deltallh

The Madison elasticity behavior is also preserved.

Conversion workflow

Current unified files:

workflows/conversion/conversion.py
workflows/conversion/exe.sh
workflows/conversion/condor.sub

Original working Madison files are preserved under:

workflows/conversion/reference/condor/

The current Condor workflow is intentionally based on:

one Condor job
    -> one I3 file
    -> one SQLite database

The current GraphNeT I3ToSQLiteConverter automatically derives the SQLite
filename from the I3 basename, so no merge operation is required for this
single-file workflow.

The pulse series is configurable and is passed through:

condor.sub
    -> exe.sh
    -> conversion.py

Examples:

SplitRTCleanedInIcePulses
SRTInIcePulses

GCD/I3 matching remains external to the core workflow. A manifest may provide
one (GCD path, I3 path) pair per Condor job.

Madison environment

The existing Madison environment compatibility layer is intentionally
preserved for the first deployment test:

CVMFS IceCube setup
IceTray env-shell
private GraphNeT Python environment
private Python site-packages / NumPy handling

These components have already supported working Madison conversions and should
not be removed or simplified before real Condor testing.

The current reference environment includes:

/cvmfs/icecube.opensciencegrid.org/py3-v4.4.2/setup.sh
/data/user/mlarson/icetray/build/env-shell.sh
/data/user/jliao/envs/mlarson_graphnet_env/bin/python3

The old Madison PYTHONPATH points to the old custom GraphNeT checkout.
During deployment it must be changed to the src directory of the unified
Git checkout being tested.

Reconstruction workflows

Cross-environment reconstruction entry points:

workflows/reconstruction/energy.py
workflows/reconstruction/track_cascade.py
workflows/reconstruction/direction_vertex.py

Original working PACE scripts are preserved under:

workflows/reconstruction/reference/pace/

PACE regression wrappers are under:

workflows/reconstruction/pace/
Energy

Model:

models/energy/energy_model.pth

Detector preprocessing:

IceCubeDeepCore

IceCubeDeepCore is NOT equivalent to IceCube86 in this GraphNeT version.
The trained Energy model itself contains an IceCubeDeepCore detector and
this preprocessing contract must be preserved.

Status:

PACE regression smoke test: PASSED
Track / Cascade

Model:

models/track_cascade/track_cascade_model.pth

Detector preprocessing:

IceCube86

Status:

PACE regression smoke test: PASSED

Known non-blocking issue:

CSV column `target_pred` should eventually be renamed to `track_score`.
Prediction values are unaffected.
Direction / Vertex

Model:

models/direction_vertex/direction_vertex_model.pth

Detector preprocessing:

IceCube86

The existing trained model depends on custom GraphNeT components including:

JointPositionandDirectionReco
JointLabel
JointLoss

The model prediction contract is:

position_x
position_y
position_z
dir_x
dir_y
dir_z
direction_kappa

The training target contains six values:

position_x
position_y
position_z
dir_x
dir_y
dir_z

JointLoss combines the position and direction losses using the behavior
implemented in the existing code:

combined_loss = alpha * position_loss + direction_loss

Status:

PACE regression smoke test: PASSED
Reconstruction model verification

See:

models/MODELS.md

The three deployment models are tracked with SHA256 checksums.

Current validation status

The following unified reconstruction workflows have been tested successfully on
PACE using the same SQLite database:

Greco_0610_Run00142709.db

Results:

Energy             PASSED
Track / Cascade    PASSED
Direction / Vertex PASSED

All three produced expected CSV reconstruction output with reasonable values.

Next milestone

The next deployment milestone is Madison / HTCondor validation using a fixed
Git commit of this repository:

1. Commit and push the unified integration branch.
2. Clone/checkout the exact commit on Madison.
3. Point Madison PYTHONPATH to that checkout's `src` directory.
4. Preserve the existing IceTray/CVMFS/private-Python environment.
5. Run a real GCD + I3 conversion.
6. Verify the resulting SQLite schema and event counts.
7. Run Energy, Track/Cascade, and Direction/Vertex reconstruction on Condor.
8. Compare the Condor reconstruction output against the validated PACE
   behavior.

The workflow is considered successfully migrated only after the complete:

I3 -> SQLite -> Energy / TC / DV

chain runs successfully on Madison / HTCondor.

