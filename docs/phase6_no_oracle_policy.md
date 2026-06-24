# Phase 6 No-Oracle Policy

Status: scaffold and audit boundary.

Forbidden production inputs include:

- true DL or UL channel tensors for CSI, SRS, PMI, TPMI, rank, beam, precoder,
  MU pairing, or scheduler decisions
- expected CRI, RI, PMI, CQI, TPMI, beam, or SRS answers
- UE private CSI-RS measurements read directly by the gNB scheduler
- transmit-side CSI-RS/SRS resource rows counted as receive-side success
- configured rank treated as measured RI
- MU-MIMO claims without overlapping PRBs, overlapping symbols, independent
  streams, compatible DM-RS, interference-aware processing, and per-user decode
  evidence

Allowed reference use:

- post-run scoring, NMSE, reconciliation, and negative corruption tests
- independent reference vectors from MATLAB 5G Toolbox or analytical channels
- configuration legality checks before runtime

The current boundary inventory is `phase6_baseline/current_oracle_fields.csv`.
