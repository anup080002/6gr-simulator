# Phase 6 Test Plan

Status: staged plan.

The first guard is `tests/testPhase6BaselineScaffold.m`, which verifies that the
Phase 6 source maps, no-oracle inventory, traceability rows, and gate evaluator
exist and remain honest.

Focused test families for later implementation:

- CSI-RS resource mapping, sequence, beam sweep, extraction, RSRP, SINR, CRI,
  RI, PMI, and CQI
- CSI report bit layout, Part 1, Part 2, PUCCH Format 2 encoding, waveform
  transmission, decoding, and scheduler state update
- SRS mapping, waveform, receiver, channel estimate, rank, TPMI, reciprocity,
  calibration, age, and prediction
- TRS residual CFO/timing/common-phase tracking and PTRS before/after EVM
- rank-2 PDSCH and PUSCH layer evidence, total-power normalization, HARQ, and
  CRC
- DL/UL MU-MIMO candidate rejection, shared-resource selection, precoding or
  joint reception, interference accounting, and per-user decode/HARQ evidence
- no-oracle corruption tests proving production output is unchanged when hidden
  truth references are poisoned
