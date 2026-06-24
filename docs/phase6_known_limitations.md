# Phase 6 Known Limitations

Status: `Phase6Ok` is false.

This branch starts Phase 6 by recording traceability and evidence gates. It does
not yet prove the complete advanced-PHY runtime.

Current limitations:

- decoded RRC ownership of all CSI/SRS/TRS/PTRS/codebook resources is pending
- PUCCH Format 2 CSI report over-air integration is pending
- scheduler consumption of decoded CSI reports is pending
- SRS strict helpers exist, but connected scheduler use and reciprocity aging
  evidence are pending
- TRS strict helpers exist, but full coupled-runtime tracking improvement
  evidence is pending
- PTRS before/after EVM evidence is partial
- rank-2 PDSCH/PUSCH must not be claimed from configured rank alone
- DL and UL MU-MIMO require shared PRB/symbol runtime decode evidence and remain
  pending until that evidence exists
- full scenario `ResultOk` must remain governed by later channel/RF, duration,
  KPI, multi-seed, and publication-readiness gates
