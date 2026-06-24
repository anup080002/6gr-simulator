# Phase 6 Existing Advanced-PHY Gaps

This baseline was recorded on branch `fix/phase6-csi-srs-rank2-mumimo`.
It is an inventory and gate scaffold, not a Phase 6 acceptance result.

`Phase6Ok` remains false until every gate in
`+sixgr/+runtime/Phase6TruthEvaluator.m` is backed by runtime evidence.

## Current explanations to verify with runtime evidence

| Observation | Current best classification | Phase 6 follow-up |
| --- | --- | --- |
| Configured rank 2 but effective rank 1 | partial MIMO operating-point evidence | Prove measured RI/rank-2 eligibility from CSI/SRS and live two-layer decode; do not infer from configured maximum rank. |
| Zero exact configured/effective rank match | expected when rank is configured but not demonstrated | Keep configured rank separate from effective decoded rank in evidence tables. |
| No strict SRS evidence | existing strict SRS helpers are not yet tied into the connected Phase 6 scheduler loop | Add decoded RRC ownership, live UL channel/RF application, received SRS estimate, age, and scheduler consumption. |
| No strict TRS evidence | strict TRS helpers exist but coupled runtime tracking improvement is pending | Add received TRS-derived CFO/timing/common-phase before/after evidence under impairments. |
| Incomplete PUCCH evidence | PUCCH Format 0/1 evidence exists; Format 2 CSI report path is pending | Implement capacity validation, UCI coding, waveform transmission, decode, and report semantic validation. |
| No demonstrated MU-MIMO | scheduler lineage alone is insufficient | Require overlapping PRBs/symbols, distinct streams, compatible DM-RS, interference-aware processing, per-user CRC, and HARQ evidence. |

## Do-not-claim list

- Do not mark any traceability row `complete` from this scaffold.
- Do not treat diagnostic CSI/SRS/TRS runs as full connected Phase 6 evidence.
- Do not promote proxy, fallback, or transmit-side-only rows into primary Phase 6
  result tables.
- Do not use `Phase6Ok` as full scenario `ResultOk`.
