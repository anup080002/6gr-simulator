# MAC, HARQ and Scheduling — Limited Execution Report

## Scope

This report validates the generated implementation pack and audits the uploaded source for the MAC/HARQ/scheduling phase. It does not claim that the current MATLAB production chain passes, because MATLAB and Octave are unavailable in this environment.

The technical scope is the actual event/state/timing/HARQ/scheduler/MAC-PDU implementation. It excludes release branding and generic truth-contract work.

## Pack contents validated

- Independent manifest: **33 files / 4,773 rows**
- Capability profile matrix: **48 tuples**
- Static source checks: **60**
- Targeted defect checks: **48**
- Detected targeted source defects: **47**
- Useful implementation foundations: **12**
- Mandatory MATLAB test plan: **60 tests**
- Relevant existing MATLAB tests found: **37 files**
- Impact families: **64**
- Controlled impact experiments: **768**
- Impact acceptance rules: **96**
- Base output contract: **32 CSVs / 22 PNGs**
- Impact output contract: **16 CSVs / 30 PNGs**
- Combined required production artifacts: **48 CSVs / 52 PNGs / 100 total**

## Current source result

The uploaded simulator currently fails this phase. The source audit found **47 targeted defect signatures** out of 48 checks.

Major classes are:

1. a generic HARQ entity that self-identifies as simple;
2. synthesized HARQ process expiry from RTT/K1/fixed slot counts;
3. Boolean ACK/NACK feedback and incomplete DTX/codebook ownership;
4. fragmented K0/K1/K2 timing and next-UL-slot fallback;
5. configured SearchSpace/CORESET/BWP/DAI and bootstrap MCS state entering the scheduler path;
6. simple PRB chunking and unconditional retransmission-first policy;
7. approximate 8-bit BSR and PH/PCMAX quantization;
8. a pragmatic/best-effort MAC PDU parser and drop-last-SDU shortcut;
9. scalar-priority LCP without PBR/BSD/Bj;
10. no canonical MAC event store, central eligibility engine, connected TAG/timeAlignmentTimer, or complete SR state;
11. no integrated SPS/configured-grant state;
12. incomplete per-cell HARQ isolation, atomic grant commit, packet lineage, and byte conservation.

Useful foundations already present and intended for reuse are:

- position-aware soft combining;
- mother-code position storage;
- coding-layout hash checking;
- an NDI epoch;
- first-success delivery de-duplication;
- PF and RR policy baselines;
- an exact-PHY grant-finalization hook;
- basic BSR and PHR helpers;
- TB metadata carrying HARQ process information;
- a Msg3 timing-advance waveform helper.

## Exact table/vector result

The pack verifier passed:

```text
Manifest files:       33 / 33
Protected rows:       4,773
BSR 5-bit rows:       32 / 32
BSR 8-bit rows:       256 / 256
Refined BSR rows:     256 / 256
PH mapping rows:      64 / 64
PCMAX mapping rows:   64 / 64
Impact families:      64 / 64
Impact experiments:   768 / 768
Acceptance rules:     96 / 96
Failures:             0
```

These are bounded independent table/state floors. They do not substitute for executing the corrected production MATLAB chain.

## Current CSV and image status

Repository inventory:

- CSV files inspected: **225**
- Rectangular CSV files: **224**
- Malformed/nonrectangular CSV files: **1**
- PNG files inspected: **40**
- PNG files decoded: **40**
- Structurally nonblank PNG files: **40**

The malformed existing CSV is:

```text
tmp_geom_cfg_export_manual/run/reports/csv/phase7_truth_gates.csv
```

Contracted MAC artifacts present:

- Required CSVs: **0 / 48**
- Required PNGs: **0 / 52**
- Total: **0 / 100**

The existing figures are generic geometry, SINR, throughput, queue and site-layout outputs. They do not verify event-sourced state, HARQ process transitions, NDI/RV identity, K0/K1/K2 timing, feedback codebooks, soft-buffer provenance, exact BSR/PHR mappings, LCP token buckets, MAC PDU composition, TA/TAG behavior, scheduler fairness, decoded-grant authority, packet lineage or byte conservation.

## Non-MATLAB test result

| Status | Count |
|---|---:|
| PASS | 18 |
| WARN | 1 |
| FAIL | 2 |
| BLOCKED | 2 |

The two failures are expected before Codex applies the remediation:

- the current production source still contains 47 targeted defects;
- none of the 100 contracted production artifacts exists yet.

The two blocked items are:

- actual production MATLAB/5G Toolbox execution;
- execution of 37 relevant existing repository MATLAB tests.

## Verifier self-tests

Base artifact verifier:

```text
Valid synthetic artifact set:
    CSVs: 32 / 32
    PNGs: 22 / 22
    failures: 0
    exit code: 0

Injected corruption:
    png_hash_mismatch:mac_event_state_timeline.png
    exit code: 2
```

Impact artifact verifier:

```text
Valid synthetic impact set:
    experiments: 768 / 768
    rules: 96 / 96
    CSVs: 16 / 16
    PNGs: 30 / 30
    failures: 0
    exit code: 0

Injected corruption:
    png_hash_mismatch:mac_impact_harq_process_count.png
    exit code: 2
```

## Runtime limitation

No MATLAB executable and no Octave executable are installed. Therefore, this environment did not execute:

- the corrected event-sourced MAC state projections;
- actual decoded DCI/UCI-to-HARQ closed loops;
- PDSCH/PUSCH HARQ retransmission campaigns;
- exact PUCCH feedback-codebook integration;
- SPS or configured-grant state machines;
- BSR/PHR/SR CEs through live MAC PDU assembly and decoding;
- timing-advance sample application and timeAlignmentTimer gating;
- multi-UE PF/RR/QoS-PF/EDF traffic campaigns;
- two-cell/cross-carrier state isolation;
- packet-to-TB-to-delivery conservation;
- production CSV and PNG generation.

Those remain mandatory in the Codex prompt and must be recorded as `BLOCKED`, not `PASS`, until run on the pinned MATLAB/5G Toolbox release.
