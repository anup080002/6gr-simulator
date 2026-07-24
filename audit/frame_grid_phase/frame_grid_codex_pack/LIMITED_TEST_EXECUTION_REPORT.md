# Limited execution report — frame, grid, numerology and duplexing

## Scope

This report covers only the first technical remediation area of the uploaded 6GR MATLAB simulator:

- numerology and cyclic prefix;
- carrier transmission-bandwidth configuration and minimum guardband;
- OFDM sampling ownership;
- TDD common/dedicated symbol ownership;
- FDD separation;
- allocation legality;
- SSB/PRACH timing ownership;
- BWP/component-carrier state;
- K0/K1/K2 absolute timing;
- required CSV and PNG diagnostics.

The analysis repository was:

```text
/mnt/data/6gr_work/6GR Simulator_v2_clean_main
```

MATLAB and Octave were not installed in the execution environment. Therefore no MATLAB waveform, `nrOFDMInfo`, `nrOFDMModulate`, `nrOFDMInfo`, 5G Toolbox, or `matlab.unittest` execution was possible here.

## Test vectors prepared

| Vector set | Rows | Purpose |
|---|---:|---|
| Numerology/CP | 18 | mu 0–6, normal CP, extended CP positive/negative cases, invalid SCS |
| Carrier grid | 71 | Every TS 38.104 FR1, FR2-1 and FR2-2 bandwidth/SCS table cell, including N/A, exact NRB and minimum guardband |
| TDD common/dedicated | 11 | Common pattern, pattern2, invalid periodicity, overbooking, reference-SCS relation, dedicated overrides, extended CP |
| Allocation legality | 14 | PDCCH/PDSCH/PUSCH/PUCCH/PRACH use of fixed and flexible symbols, conflicts and explicit grants |
| **Total** | **114** | |

The pack-integrity validator executed 36 consistency checks over these files and their derived golden outputs. Result:

```text
36 passed
0 failed
```

## Golden expected CSVs

The following expected outputs were generated from the pinned table values and deterministic TDD/allocation vectors. They are test oracles, not current simulator output:

| CSV | Rows | Integrity |
|---|---:|---|
| `expected_frame_numerology_matrix.csv` | 18 | PASS |
| `expected_carrier_grid_matrix.csv` | 71 | PASS |
| `expected_slot_symbol_ownership.csv` | 510 | PASS |
| `expected_allocation_legality.csv` | 14 | PASS |

Every row has `Status=PASS`; hashes are recorded in `expected_output_integrity_audit.csv`.

## Current uploaded implementation results

### Static shortcut checks

All 12 targeted frame-layer shortcuts were detected in the current source. The detailed file/line evidence and source hashes are in `current_frame_static_audit.csv`.

```text
12 detected
12 current failures
```

The detected areas are:

1. incomplete role-aware numerology/CP validation;
2. configured-grid fallback after a failed standard table lookup;
3. next-power-of-two FFT fallback;
4. conversion of flexible TDD symbols to DL;
5. silent 12/1/1 special-slot default;
6. PDSCH start derived from CORESET duration;
7. SSB grid clamp/retry;
8. sparse PRACH-index handling;
9. implicit 2.5%-NFFT windowing;
10. single copied BWP surface;
11. no canonical component-carrier state in the frame engine;
12. distributed K0/K1/K2 timing ownership.

### Carrier-grid comparison

All 71 Release-18 carrier table cells were compared to the current `FrameStructureEngine` lookup behavior.

```text
54 matched
17 mismatched
```

The mismatches include missing valid FR1 rows and FR2-2 rows that the current code routes through an `FR3` token. Full per-row results are in `current_carrier_grid_comparison.csv`.

### Flexible-symbol regression

Four direct preservation inputs were evaluated against the current expansion logic:

```text
DFFU   -> current DDDU
FFFF   -> current DDDD
DDDFUU -> current DDDDUU
DFUF   -> current DDUD
```

Result:

```text
0 passed
4 failed
```

The detailed output is in `current_tdd_flexible_symbol_regression.csv`.

## Existing CSV and image outputs

### Existing PNG files

Forty PNG files found in bundled sample run directories were decoded, checked for dimensions, nonzero file size, pixel variation, nonblank content, and SHA-256.

```text
40 structurally valid
0 decode/nonblank failures
```

This does **not** establish frame-layer semantic correctness. The inspected files are geometry/system plots such as SINR, throughput, queue, trajectories, site layout and attachment maps. They are not the seven required frame/grid plots and many are approximately 710×590 rather than the new phase minimum of 1200×650.

### Required frame/grid images

None of these currently exists in the bundled sample outputs:

```text
frame_slot_symbol_map.png
resource_grid_occupancy.png
numerology_timing_matrix.png
carrier_guardband_map.png
k0_k1_k2_timeline.png
bwp_switch_timeline.png
component_carrier_resource_map.png
```

Therefore current status is:

```text
Required frame/grid image presence: 0/7
Current frame/grid image semantics verified: 0/7
```

### Existing CSV files

Five selected existing CSV files parsed successfully and were rectangular/nonempty. They are not the eleven required frame/grid CSVs.

All 18 required phase artifacts—seven PNGs and eleven CSVs—are absent from the bundled sample runs. See `existing_frame_artifact_presence_audit.csv`.

## Reference-image checks

Four table/vector-derived reference visualizations were generated to show desired diagnostic content. These are not simulator outputs.

```text
4 decoded
4 nonblank
4 dimension checks passed
4 hashes recorded
```

See `reference_image_integrity_audit.csv`.

## Post-run verifier self-test

`verify_frame_artifacts.py` was compiled and tested with a complete synthetic artifact directory.

Positive self-test:

```text
25 checks passed
0 failed
exit code 0
```

Negative self-test with one intentionally corrupted image hash:

```text
24 checks passed
1 failed
exit code 2
```

The verifier checks:

- every required CSV and PNG exists;
- CSV rectangularity, required columns and unique keys;
- all output rows have `Status=PASS`;
- mandatory test summaries have zero failed/skipped/blocked tests;
- PNG decode, dimensions, file size, variation and nonblank fraction;
- image hashes and source-CSV hashes;
- each image has exactly one matching `frame_image_audit.csv` row;
- recorded MATLAB semantic axes/series counts match expectations.

The verifier cannot independently infer whether a plotted curve is physically correct. The prompt therefore requires MATLAB to compare figure `XData`, `YData` and `CData` against the source table before export.

## What remains blocked here

The following can only be established after Codex modifies the repository and runs MATLAB with 5G Toolbox:

- exact `nrOFDMInfo` NFFT, sample-rate and CP behavior;
- no-channel OFDM round-trip NMSE/EVM;
- waveform sample counts;
- complete SSB candidate timing and no-clamp behavior;
- complete PRACH occasion timing;
- mixed-numerology BWP switching;
- two-component-carrier independence;
- K0/K1/K2 and N1/N2 timing legality;
- actual generation and semantic verification of all seven required images;
- complete MATLAB regression-suite status.

The Codex prompt defines these as mandatory completion gates rather than optional follow-up work.
