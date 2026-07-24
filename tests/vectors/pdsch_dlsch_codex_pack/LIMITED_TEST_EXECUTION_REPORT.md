# PDSCH and DL-SCH Codex pack — limited execution report

## Purpose

This report records the checks that could be executed without MATLAB. It does not claim that the PDSCH/DL-SCH PHY chain has passed. The production MATLAB source has not been modified by this pack; the Codex prompt instructs Codex to perform that implementation.

## Environment

```text
Repository: /mnt/data/6gr_src/6GR Simulator_v2_clean_main
MATLAB executable: not installed
Octave executable: not installed
Python vector-pack verifier: available and executed
Python artifact verifier: available and self-tested
Pillow PNG decoder: available
```

Because MATLAB and the 5G Toolbox are absent, the following remain blocked in this environment:

- production PDSCH transmitter execution;
- production PDSCH receiver execution;
- explicit LDPC encode/decode execution through MATLAB;
- OFDM waveform generation and demodulation;
- DM-RS/PT-RS Toolbox cross-regressions;
- AWGN, TDL, and CDL BLER campaigns;
- rank 1–8 no-noise waveform round trips;
- PRG precoder application in the production grid;
- HARQ rate-recovery and soft-combining runtime tests;
- required production CSV and PNG generation;
- MATLAB figure-object semantic verification.

## Supplied executable vectors

The pack contains 380 input rows:

| Vector set | Rows |
|---|---:|
| PDSCH scrambling | 12 |
| Modulation including negative cases | 24 |
| Rank/codeword layer mapping | 12 |
| TBS/base-graph coding inputs | 23 |
| DM-RS configuration inputs | 175 |
| Dynamic/SPS/calibration scheduling-assignment inputs | 22 |
| PT-RS inputs | 56 |
| Reserved-RE union inputs | 14 |
| Wideband/PRG precoding inputs | 15 |
| HARQ transition inputs | 11 |
| End-to-end declared coverage matrix | 16 |
| **Total** | **380** |

The pack contains 518 deterministic expected rows:

| Expected set | Rows |
|---|---:|
| Scrambling | 12 |
| Modulation | 24 |
| Layer mapping | 40 |
| TBS/base graph | 23 |
| TB CRC | 18 |
| DM-RS symbol positions | 175 |
| DM-RS port table | 108 |
| Scheduling-assignment result | 22 |
| PT-RS presence | 56 |
| Reserved-RE union | 14 |
| Precoding behavior | 15 |
| HARQ transition | 11 |
| **Total** | **518** |

These expected rows are generated without MATLAB or 5G Toolbox. They cover deterministic bounded cases and are not substitutes for the additional independent LDPC, rate-matching, DM-RS sequence, PT-RS index, precoding, HARQ, and receiver oracles required by the Codex prompt.

## Vector integrity result

```text
Files listed in manifest: 25
SHA-256 mismatches:        0
Row-count mismatches:      0
Missing files:             0
Result:                    PASS
```

The generator, every listed CSV, and `expected_output_integrity_audit.csv` are bound by `independent_vector_manifest.json`.

## Mathematical and structural limited tests

`run_limited_pdsch_tests.py` executed 26 checks:

```text
PASS:    25
FAIL:     0
BLOCKED:  1  (MATLAB runtime unavailable)
```

The passing checks include:

- manifest and SHA-256 verification;
- full-constellation mean energy of one for QPSK, 16QAM, 64QAM, 256QAM, and 1024QAM;
- all supplied CRC-appended blocks divide to zero under the selected polynomial;
- scrambling lengths and one-count consistency;
- codeword-index-dependent scrambling sequence differentiation in paired cases;
- rank 1–8 layer-count and symbol-conservation checks;
- TBS, base-graph, and CRC structural invariants;
- all passing DM-RS positions remain inside the specified PDSCH allocation;
- exact DM-RS logical/physical port capability, non-contiguous enhanced single-symbol port sets, CDM groups, deltas, and orthogonal-cover-code weights;
- reserved-RE union/data partition arithmetic;
- assignment vectors use only the declared DCI 1_0, 1_1, and 1_2 formats;
- downlink SPS vectors require a CRC-valid, correctly addressed activation DCI context and an exact SPS occasion rather than bare configuration; CRC failure and activation-RNTI mismatch are negative cases;
- declared coverage contains rank 1–8 and mapping types A/B;
- high-rank coverage selects enhanced DM-RS when the basic port capacity is insufficient;
- every declared coverage row selects only supported DM-RS ports;
- HARQ NDI remains stable across retransmissions and toggles for new data;
- source-shortcut audit execution;
- current required-artifact presence scan;
- current repository PNG decode/nonblank scan;
- artifact-verifier positive and corruption tests;
- Python compilation of pack scripts.

Machine-readable results:

- `limited_pdsch_test_results.csv`
- `limited_test_summary.json`

## Current production-source static result

The source-specific audit performed 29 targeted checks:

```text
Confirmed shortcut/defect signatures: 25
Existing useful implementation features: 4
Current static result: FAIL
```

The four positive features found in production source are:

1. an explicit rank 1–8 guard;
2. the rank-5 two-codeword split `[2,3]`;
3. codeword-specific rate-matching calls;
4. a receiver HARQ soft-combining path.

They are useful foundations but do not prove complete end-to-end behavior.

The 25 detected shortcut signatures include:

- connected waveform grant materialized from configuration;
- missing PRB allocation replaced with the full grid;
- missing symbol allocation replaced with a full normal-CP slot;
- DM-RS port overwrite;
- five DM-RS clamp paths;
- missing modulation changed to QPSK;
- multi-codeword modulation repeated or truncated;
- invalid mapping type A changed to B;
- PT-RS density/offset/port defaults;
- per-PRG precoding rejection;
- custom DM-RS port rejection;
- explicit precoder discard/regeneration;
- inferred/floored NRE per PRB;
- reconstructed G;
- connected PDSCH creation from config/frozen grant;
- post-generation CSI-RS collision handling;
- catch-all zero-grid fallback;
- policy-optional PDCCH/PDSCH binding.

See `current_pdsch_static_audit.csv` for file-level evidence and `pdsch_dlsch_12_findings.csv` for the 12 implementation themes and required corrections.

## Current CSV artifact result

The existing source tree contains two PDSCH-named CSV files:

1. `phase5_baseline/existing_pdsch_pusch_source_map.csv`
2. `tmp_geom_cfg_export_manual/run/air_interface/csv/dl_pdsch_trials.csv`

The latter has 8 rows and 273 columns and contains broad system-run trial evidence. It is not a substitute for the required assignment, RE ownership, DM-RS, PT-RS, coding, precoding, HARQ, independent-vector, BLER, and semantic-image CSVs.

Required phase artifacts currently present:

```text
Required CSV files: 15
Required PNG files:  9
Present:             0 / 24
Result:              FAIL / not yet implemented
```

See `existing_pdsch_artifact_presence_audit.csv`.

## Current image result

The repository contains 40 PNG files in bundled output folders.

```text
Decoded successfully: 40 / 40
Structurally nonblank: 40 / 40
Required PDSCH phase PNGs present: 0 / 9
```

The 40 existing images are system/geometry/SINR/throughput-style outputs. They do not establish correct PDSCH resource ownership, DM-RS/PT-RS mapping, codeword-layer mapping, PRG application, HARQ RV behavior, PDSCH BLER, PT-RS phase tracking, per-layer SINR, or reserved-RE impact.

Therefore, the required PDSCH image semantics cannot yet be verified. They must be generated by the corrected MATLAB phase runner and then checked by `verify_pdsch_artifacts.py`.

See `existing_pdsch_image_integrity_audit.csv`.

## Artifact-verifier self-test

The verifier was tested with a complete synthetic artifact directory that satisfied all schemas and numerical invariants:

```text
Checks: 33
Passed: 33
Failed: 0
Exit code: 0
```

A recorded PNG SHA-256 was then intentionally corrupted without changing the image:

```text
Checks: 33
Passed: 32
Failed: 1
Detected reason: png_hash_mismatch
Exit code: 2
```

This confirms that the verifier accepts a complete structure and rejects an integrity mismatch. It does not validate the simulator until it is run on production-generated artifacts.

## What Codex must still execute

The full prompt requires Codex to produce runtime evidence for:

- decoded DCI plus UE-context dynamic assignment ownership and activated downlink-SPS occasion ownership;
- exact type-0/type-1 FDRA and TDRA;
- exact DM-RS sequence, ports, indices, and combinations;
- exact PT-RS presence, indices, and CPE correction;
- exact reserved-resource ownership and G/TBS effects;
- explicit TB CRC, segmentation, LDPC, rate matching, scrambling, modulation, and layer mapping;
- rank 1–8 and two-codeword no-noise round trips;
- wideband and PRG precoder application;
- receiver-derived SINR/EVM/BER/BLER;
- position-aware HARQ combining;
- BWP/CC/TCI/QCL and bounded multi-TRP binding;
- all 15 CSV and 9 PNG artifacts;
- all mandatory independent vector families;
- all focused and existing MATLAB regression tests.

Until those MATLAB tests run and the artifact verifier returns exit code 0, the PDSCH/DL-SCH phase status is **not complete**.
