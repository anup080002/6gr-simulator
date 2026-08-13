# RAN1 10.5.2.3 UL repository inventory

Inventory completed before production edits from clean `main` at `e4cbc4f74a971ead597625da644901d9b554a44b`.

## Authoritative supplied inputs

- Master prompt SHA-256: `7b5fb1f32c0159971fe8e494a48f634bf1c213a372e2c8c24557a85a33ff2b5d`
- Scenario catalog SHA-256: `f0f9ab384aec584d9d4d11a9a1086525abd1cde7ffbcc165679d38ac767fbafd`
- Figure contract SHA-256: `5d5c37e56f8d32af47749d2b8888f894d53156bfd67398578224c4312dbb8773`
- Proposal traceability SHA-256: `3c6a1bb3524280cd96c91bb436a2ce1d2fe2d7cec2d1d9e63dda90ae7856b666`
- Named DOCX `R1-26xxxx_Jio_Uplink_Transmission_Schemes_6GR_Maastricht_v2.docx`: not supplied. Exact DOCX-equivalence is blocked.

## Canonical reusable UL chain

`sixgr.lls6g.config.loadScenarioConfig` resolves and validates YAML. Calibration execution uses `sixgr.link.runULPUSCHThroughput`, which calls `sixgr.phy.ul.PUSCH_Tx`, the configured channel/replay path, `sixgr.phy.ul.PUSCH_Rx`, UL-SCH/CRC and strict receiver evidence. Integrated execution is owned by `sixgr.truth.runWaveformLinkBundle`, immutable grant snapshots and `sixgr.truth.executeGrantPHYJob`.

PUCCH/UCI uses `sixgr.link.runPUCCHWaveformTrial` and the canonical `sixgr.phy.pucch` implementation. Causal SRS measurement uses `sixgr.phy.ul.estimateSRSRITPMI` and `sixgr.phy.srs`. The study layer must orchestrate these implementations and must not create a second PHY.

## Reuse and gap summary

| Domain | Existing authority | Status before this phase | Required action |
|---|---|---|---|
| PUSCH waveform | `+sixgr/+phy/+ul/PUSCH_Tx.m`, `PUSCH_Rx.m` | reusable | Execute unchanged for bounded baseline evidence |
| UL-SCH/UCI | `nrULSCH`, PUSCH UCI mux/demux package | reusable/partial | Retain exact Toolbox-backed ownership; gate unsupported multi-CW candidates |
| Assignment | `PUSCHSchedulingAssignment`, `PUSCHAssignmentFactory` | reusable | Keep one immutable executed assignment |
| Frequency hopping | `PUSCHFrequencyHopPlan` | reusable | Deterministic mapping audit; candidate FSP physics separately gated |
| Power | PUSCH power controllers and runtime ledger | reusable/partial | Add independent fixed-total-power analytical oracle |
| DM-RS/PT-RS | PUSCH Tx/Rx, reference-signal helpers | reusable/partial | Baseline real execution; candidate boosts/segment modes gated unless exercised |
| PUCCH/UCI | full `+sixgr/+phy/+pucch` package | reusable | Run bounded native PUCCH only; novel two-family candidate remains gated |
| SRS/TPMI | `estimateSRSRITPMI`, `+sixgr/+phy/+srs` | reusable | Require causal measured decisions for any calibrated claim |
| Scheme 2 | `BeamformingSRSReciprocity` and measurement surfaces | partial | Exact matrix/report arithmetic available; calibrated procedure matrix missing |
| FSP | PRG/precoder and hop primitives | partial | Exact combinatorial and mapping oracles; groupwise waveform campaign missing |
| Multi-slot/TBoMS | no complete canonical single-TB cross-slot owner | blocked | Do not synthesize results |
| MRSS UL | no proven UL network-transparent SLS implementation | blocked | Do not relabel PDSCH/abstract SLS |
| Antenna selection | antenna and SRS components exist | partial | Genuine per-drop selection LLS/SLS remains required |
| Artifacts | repository reporting, raster and hashing utilities | reusable | Add study-specific persisted-CSV replay and fail-closed publication gate |

## Baseline risks checked

- Fading receiver must retain per-resource channel estimates.
- Configured TPMI/SNR/rank cannot be exported as measured values.
- Grant-level TBS must come from the executed allocation.
- Proxy or quick-sanity rows cannot enter calibrated primary tables.
- C15, C22 and the SLS part of C24 cannot be decided using LLS-only evidence.
- Candidate mechanisms absent from canonical Tx/Rx must remain `BLOCKED`.
