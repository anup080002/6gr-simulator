# Frame/grid Codex implementation pack

This is the first **technical implementation** phase for the 6GR MATLAB simulator. It is scoped to frame structure, carrier/resource grids, numerology, duplexing, BWP/component-carrier state, and K0/K1/K2 timing. It does not ask Codex to write a review or a standards-claim document.

## Main implementation prompt

- `CODEX_PROMPT_01_FRAME_GRID_NUMEROLOGY_DUPLEXING.md` — paste this into Codex while Codex is opened at the repository root. It orders Codex to edit MATLAB source, migrate callers, add tests, run them, emit CSV/PNG artifacts, verify them, and continue until the phase passes.

## Executable input vectors

- `frame_numerology_test_vectors.csv` — 18 valid/invalid numerology and CP inputs.
- `frame_carrier_grid_test_vectors.csv` — 71 valid/N-A gNB carrier bandwidth/SCS table cells for FR1, FR2-1, and FR2-2, with exact minimum guardbands.
- `frame_tdd_test_vectors.csv` — 11 common/dedicated TDD patterns, including flexible-symbol and extended-CP cases.
- `frame_allocation_test_vectors.csv` — 14 legal/illegal PDCCH/PDSCH/PUSCH/PUCCH/PRACH allocation cases.

## Golden desired CSV examples

These are table-derived expected outputs for the supplied limited input vectors, not captured output from the current simulator:

- `expected_frame_numerology_matrix.csv` — 18 rows.
- `expected_carrier_grid_matrix.csv` — 71 rows.
- `expected_slot_symbol_ownership.csv` — 510 per-symbol rows.
- `expected_allocation_legality.csv` — 14 rows.

Codex must run the real production MATLAB resolvers and compare their serialized results field by field with these expected files. It must not copy the expected files into the output directory as a substitute for execution.

## Output contracts and verification

- `desired_frame_csv_contract.csv` — required schemas and pass conditions for 11 simulator-generated CSVs.
- `desired_frame_image_contract.csv` — required source CSV and semantic content for seven simulator-generated PNGs.
- `verify_frame_artifacts.py` — post-run verifier for CSV schemas/rectangularity/keys/status, test-summary counts, PNG decoding/dimensions/nonblank content, hashes, and image-to-source-CSV audit links. MATLAB must first perform semantic figure-object checks before export.
- `validate_pack_integrity.py` — validates this pack's vectors, golden outputs and recorded limited-test results; currently 36/36 checks pass.
- `LIMITED_TEST_EXECUTION_REPORT.md` — complete statement of what was and was not executable in this environment.

## Current uploaded-code audit

- `current_frame_static_audit.csv` — 12/12 targeted shortcuts detected.
- `current_carrier_grid_comparison.csv` — all 71 carrier vectors checked against the current lookup; 17 mismatches.
- `current_carrier_grid_extra_entries.csv` — current non-table/extra rows found.
- `current_tdd_flexible_symbol_regression.csv` — 4/4 flexible-symbol preservation tests fail because `F` is converted to `D`.
- `existing_output_image_integrity_audit.csv` — 40 existing PNGs decoded and passed structural/nonblank checks.
- `existing_output_csv_integrity_audit.csv` — five selected existing CSVs parsed and were rectangular/nonempty.
- `existing_frame_artifact_presence_audit.csv` — all 18 required frame-phase CSV/PNG artifacts are absent from the bundled sample outputs.
- `limited_test_summary.csv` / `.json` — machine-readable summary.

## Reference visualizations

`reference_images/` contains four golden visualizations generated directly from the supplied expected vectors. They are not simulator output and do not prove the current MATLAB implementation. `reference_image_integrity_audit.csv` records their dimensions, nonblank metrics, hashes, and PASS status.

## Recommended Codex use

1. Copy this directory into the repository, for example `audit/frame_grid_phase/`.
2. Open Codex at the repository root.
3. Paste the complete implementation prompt.
4. Require the exact MATLAB and Python commands, CSV row counts, image hashes, and test results before Codex reports `COMPLETE`.

MATLAB and Octave were not installed in the analysis environment. Therefore waveform execution, `nrOFDMInfo` comparison, MATLAB unit tests, and semantic MATLAB figure-object verification remain blocked here; the prompt makes them mandatory in the Codex environment.
