# MIMO, CSI, Precoding and Beamforming — Limited Execution Report

## Scope

This report validates the generated implementation pack and audits the uploaded source for the MIMO/CSI/precoding/beamforming phase. It does not claim that the current MATLAB production waveform passes, because MATLAB and Octave are unavailable in this environment.

## Pack contents validated

- Independent manifest: **24 files / 4,228 rows**
- Capability profile matrix: **164 tuples**
- Static source checks: **58**
- Detected source defects: **48**
- Useful production foundations: **10**
- Mandatory MATLAB test plan: **65 tests**
- Impact families: **64**
- Controlled impact experiments: **768**
- Impact acceptance rules: **96**
- Base output contract: **28 CSVs / 20 PNGs**
- Impact output contract: **16 CSVs / 30 PNGs**
- Combined required production artifacts: **44 CSVs / 50 PNGs / 94 total**

## Current source result

The uploaded simulator currently fails this phase. The source audit found **48 targeted defect signatures**. Major classes are:

1. compact Type-I-like rank-1/rank-2 DFT candidate generation;
2. panel geometry inferred from port count and clamped parameters;
3. PMI selected using raw Frobenius gain;
4. RI selected using SVD/configured-SNR thresholds;
5. fixed custom RI/PMI/CQI payload construction;
6. generic DFT candidates labelled Type-II or enhanced Type-II;
7. matrix orientation, shape or identity fallbacks;
8. configured TPMI competing with measured SRS;
9. covariance-free IRC silently becoming MMSE;
10. geometry- or heuristic-driven beam selection;
11. incomplete high-rank, MU-MIMO, multi-TRP, CJT and hybrid-beamforming closure;
12. missing full beam-management state machine.

Useful foundations already present and intended for reuse are:

- measured-SRS RI/TPMI helper;
- downlink CSI feedback entry point;
- sample-domain spatial contribution tensors;
- ZF/MMSE/IRC detector integration;
- MIMO evidence export surface;
- PDSCH and PUSCH precoding integration points;
- CSI-RS generation integration;
- a fixed-rank no-collapse test;
- an IRC/channel-estimation test.

## Current artifact status

Repository inventory:

- CSV files inspected: **225**
- Rectangular CSV files: **224**
- PNG files inspected: **40**
- PNG files decoded: **40**
- Structurally nonblank PNG files: **40**

Contracted MIMO artifacts present:

- Required CSVs: **0 / 44**
- Required PNGs: **0 / 50**
- Total: **0 / 94**

The existing PNGs are generic system/geometry/throughput/SINR outputs. They do not verify antenna-panel geometry, exact codebook coefficients, CSI Part-1/Part-2 layout, selected-versus-applied matrices, high-rank layers, covariance quality, MU-MIMO leakage, multi-TRP phase coherence, hybrid analog/digital weights or beam-management transitions.

## Non-MATLAB test result

| Status | Count |
|---|---:|
| PASS | 16 |
| WARN | 1 |
| FAIL | 2 |
| BLOCKED | 2 |

The two failures are expected pre-remediation findings:

- the current production source still contains 48 targeted defects;
- none of the 94 contracted production artifacts exists yet.

The two blocked items are:

- actual production MATLAB waveform execution;
- execution of 28 relevant existing repository MATLAB tests.

## Verifier self-tests

Base artifact verifier:

```text
Valid synthetic artifact set:
    CSVs: 28 / 28
    PNGs: 20 / 20
    failures: 0
    exit code: 0

Injected corruption:
    png_hash_mismatch:mimo_antenna_panel_geometry.png
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
    png_hash_mismatch:mimo_impact_codebook_accuracy.png
    exit code: 2
```

## Independent-vector limitation

The supplied vector pack is deliberately a bounded independent floor. It includes an exact two-port Type-I codebook, analytical array responses, CSI bit ownership, RI/PMI objective cases, covariance cases, matrix-application cases and structural advanced-profile vectors. Codex must add exact frozen vectors for every enabled general Type-I single-panel, Type-I multi-panel, Type-II, port-selection Type-II and enhanced Type-II tuple before claiming that tuple complete.

## Runtime limitation

No MATLAB executable and no Octave executable are installed. Therefore, this environment did not execute:

- actual CSI-RS/SRS measurement waveforms;
- codebook-driven PDSCH/PUSCH transmission;
- CSI Part 1/Part 2 over PUCCH/PUSCH;
- high-rank LDPC/HARQ campaigns;
- covariance-qualified IRC;
- MU-MIMO shared-resource waveforms;
- multi-TRP or coherent JT waveforms;
- FR2 hybrid beamforming;
- beam-management mobility/blockage/recovery;
- production CSV and PNG generation.

Those remain mandatory in the Codex prompt and must be recorded as `BLOCKED`, not `PASS`, until run on the pinned MATLAB/5G Toolbox release.
