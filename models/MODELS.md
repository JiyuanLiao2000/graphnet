# Reconstruction Models

These models are the reference deployment models for the unified GraphNeT
reconstruction workflows.

## Energy

- File: `models/energy/energy_model.pth`
- SHA256: `c64b0d882cd0e025780e1b414831b1e94de06185560cbf9d693e16798a118b6a`
- Workflow: `workflows/reconstruction/energy.py`
- Detector preprocessing: `IceCubeDeepCore`
- Status: passed PACE regression smoke test

## Track / Cascade

- File: `models/track_cascade/track_cascade_model.pth`
- SHA256: `1322fd213801f680b61045c72557440239356f2e21329879011d210d666193ad`
- Workflow: `workflows/reconstruction/track_cascade.py`
- Detector preprocessing: `IceCube86`
- Status: passed PACE regression smoke test
- Known issue: output column `target_pred` should eventually be renamed
  to `track_score`. This is currently non-blocking and does not affect
  prediction values.

## Direction / Vertex

- File: `models/direction_vertex/direction_vertex_model.pth`
- SHA256: `88db3f74d0399ddf13a303b9b74dbe5ca3c68f101ed5cf607c5f037ad1f8f54c`
- Workflow: `workflows/reconstruction/direction_vertex.py`
- Detector preprocessing: `IceCube86`
- Custom model contract:
  - `JointPositionandDirectionReco`
  - `JointLabel`
  - `JointLoss`
- Status: passed PACE regression smoke test

## Verification

After copying or cloning the models to another system, verify them with:

```bash
sha256sum \
  models/energy/energy_model.pth \
  models/track_cascade/track_cascade_model.pth \
  models/direction_vertex/direction_vertex_model.pth
