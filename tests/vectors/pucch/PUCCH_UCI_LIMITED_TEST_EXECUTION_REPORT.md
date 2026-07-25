# PUCCH and UCI Implementation Pack — Limited Execution Report

## Result

The current uploaded simulator **does not pass** the PUCCH/UCI phase.

- Targeted source-visible defects/shortcuts detected: **44**
- Useful existing implementation foundations detected: **8**
- Required contracted PUCCH artifacts currently present: **0/82**
- MATLAB production execution: **BLOCKED** because MATLAB and Octave are unavailable in this environment

The pack infrastructure itself passed its deterministic and corruption-detection tests.

## Pack contents validated

- **10** implementation findings
- **31** independent-manifest files
- **4,271** deterministic vector rows
- **50** impact-analysis families
- **600** controlled baseline/treatment experiments
- **75** acceptance rules
- **23** base production CSV contracts
- **15** base technical PNG contracts
- **16** impact CSV contracts
- **28** impact PNG contracts
- **82** total required production artifacts

## Current source findings

The audit found all 44 targeted signatures, including:

- raw `uciBits` as the production report interface;
- receiver `ExpectedUCIBits` oracle input;
- receiver fallback to 20 UCI bits;
- one-bit default payload in the waveform trial;
- format-2 default and automatic format promotion/demotion;
- symbol, PRB, cyclic-shift, OCC, spreading-factor and hopping defaults/clamps;
- swallowed DM-RS and UCI-decode failures;
- six CRC bits assumed for every payload at or above 12 bits;
- hard-coded format/resource trials;
- four-slot HARQ timing default;
- scan/shift-to-fit TDD behavior;
- deterministic RNTI/cell PRB hashing;
- rectangular-only collision detection;
- ACK-only runtime feedback payloads.

Useful foundations include the existing Toolbox-backed format 0–4 configuration objects, PUCCH index/DM-RS integration points, a waveform trial harness, a strict validation entry point and a runtime grant trace.

## Deterministic vector checks

The vector verifier returned exit code **0** with zero failures. Its bounded independent floor covers:

| Family | Rows |
|---|---:|
| Typed UCI report/serialization inputs | 128 |
| UCI coding and CRC/segmentation inputs | 140 |
| Format 0–4 validation matrix | 350 |
| Resource-set selection | 70 |
| Bounded HARQ codebooks | 24 |
| SR occasion arithmetic | 414 |
| CSI report serialization | 48 |
| K1/TDD timing | 192 |
| Collision resolution | 80 |
| Power control | 48 |
| Spatial relation | 72 |
| Negative cases | 92 |
| End-to-end coverage | 84 |

The manifest contains 4,271 rows because it also includes expected outputs, impact inputs, pairing contracts, rules and analytical floors.

This is a bounded independent floor, not a claim that every Release-18 codebook, sequence and table is already externally frozen. The Codex prompt requires the missing pure-spec/frozen families to be added before completion.

## Artifact-verifier tests

### Base verifier

A synthetic complete result containing 23 CSVs and 15 PNGs was accepted. An intentionally corrupted PNG hash was rejected.

```text
valid set exit code:   0
corrupted set exit:    2
corruption detected:   png_hash_mismatch
```

### Impact verifier

A synthetic result containing all 600 experiments, 75 rules, 16 CSVs and 28 PNGs was accepted. An intentionally corrupted impact PNG hash was rejected.

```text
valid set exit code:   0
corrupted set exit:    2
corruption detected:   png_hash_mismatch
```

## Existing output inspection

- Existing PNGs inspected: **40**
- PNGs decoded: **40/40**
- Structurally nonblank: **40/40**
- Contracted PUCCH technical PNGs present: **0/43**
- Existing PUCCH-named CSVs inspected: **3**
- Rectangular current PUCCH-named CSVs: **3/3**
- Contracted PUCCH production CSVs present: **0/39**

The existing images are generic system/geometry/SINR/throughput figures. They do not verify UCI bit layout, resource-set/PRI selection, K1 timing, codebooks, format mappings, DM-RS/OCC orthogonality, power control, spatial relation or PUCCH BLER/false-alarm behavior.

## Existing Python PUCCH test

`tests/test_lls_browser_pucch_truth.py` did not reach its assertions because importing the dashboard requires this machine-specific path at import time:

```text
C:\Program Files\MATLAB\R2024a\bin\matlab.exe
```

This is recorded as **BLOCKED** rather than a PUCCH PHY pass or failure.

## MATLAB limitation

MATLAB and Octave were not installed. Consequently, the following remain mandatory for Codex to execute on the pinned MATLAB/5G Toolbox release:

- production formats 0–4 waveform generation and decoding;
- exact UCI coding and rate recovery;
- codebook, SR and CSI report procedures;
- resource-set/PRI/K1/TDD runtime integration;
- DM-RS, hopping, repetition, OCC and collision tests;
- power and spatial-relation waveform application;
- no-noise, AWGN, TDL and CDL campaigns;
- no-signal/wrong-context statistical campaigns;
- all 39 CSVs and 43 PNGs;
- complete repository MATLAB regression.

## Commands already exercised

```bash
python verify_pucch_vector_pack.py
python audit_current_pucch_source.py <repository-root>
python verify_pucch_artifacts.py --self-test
python verify_pucch_impact_artifacts.py --self-test
python tests/test_lls_browser_pucch_truth.py
```

The first four pack commands behaved as designed. The repository test was blocked by its import-time MATLAB path requirement.
