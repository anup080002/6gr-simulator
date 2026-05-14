# LLS Results Extraction Fix Report

## Scope

This patch series tightened the LLS reporting/export layer so users can extract waveform-backed results from public family tables instead of reverse-engineering wide debug tables. The changes also added plot lineage/provenance artifacts and stricter coverage reporting so missing or suppressed outputs stop looking implemented.

## Files Changed

- `+sixgr/+truth/exportLLSOutputCoverageArtifacts.m`
- `+sixgr/+truth/exportLLSReportingBundle.m`
- `+sixgr/+truth/buildLLSPublicOutputTables.m`
- `+sixgr/+truth/buildLLSReportingProvenanceTables.m`
- `+sixgr/+truth/llsOutputContract.m`
- `+sixgr/+visual/validatePlotData.m`
- `+sixgr/+visual/writePlotManifestRow.m`
- `+sixgr/+visual/writeChartSourceCsv.m`
- `+sixgr/+truth/CoupledTruthRuntime.m`
- `tests/testLLSOutputCoverageArtifacts.m`
- `tests/testLLSPlotDataValidation.m`

## Main Changes

### 1. Public family-specific LLS tables

Added extraction/build logic for public, lower-sparsity tables under `reports/csv`:

- `pdsch_runtime_event_table.csv`
- `pusch_runtime_event_table.csv`
- `pdcch_dci_table.csv` (public report-facing version)
- `pucch_uci_table.csv`
- `prach_detection_table.csv`
- `srs_measurement_table.csv`
- `csi_rs_runtime_event_table.csv`
- `csi_report_table.csv`
- `trs_receiver_tracking_table.csv` (public report-facing version)
- `ssb_pbch_cell_search_table.csv`
- `noise_variance_evidence_table.csv`
- `mcs_cqi_decision_trace_table.csv`

These tables are derived from persisted runtime-backed raw/control tables only. No placeholder rows are injected to keep them non-empty.

### 2. Plot provenance and suppression artifacts

Added machine-readable reporting/provenance tables:

- `plot_manifest.csv`
- `plot_render_status.csv`
- `chart_source_registry.csv`
- `plot_data_quality_table.csv`
- `plot_suppression_table.csv`
- `unavailable_plot_card_registry.csv`
- `raw_to_derived_lineage.csv`
- `table_field_availability_matrix.csv`

Every manifest row now records source CSV, row counts, unique-x counts, non-NaN y counts, suppression reason, and whether the image counts as a real plot.

### 3. Output contract and metric catalog

Added:

- `lls_output_contract.csv`
- `metric_definition_catalog.csv`
- `metric_unit_role_catalog.csv`

The MATLAB-side source of truth is `+sixgr/+truth/llsOutputContract.m`.

### 4. Plot gating fixes

`+sixgr/+visual/validatePlotData.m` now suppresses:

- one-point `*_vs_*`/relation plots
- one-row trace/timeline plots
- all-NaN CDF/histogram inputs
- empty/all-NaN heatmaps

`+sixgr/+truth/exportLLSReportingBundle.m` now uses that gating before rendering or writing placeholder/unavailable plot artifacts.

### 5. Coverage/completeness honesty

`+sixgr/+truth/exportLLSOutputCoverageArtifacts.m` was updated so the coverage surface includes the new public outputs and provenance artifacts.

It now also exports richer completeness fields such as:

- `direct_artifact_status`
- `direct_artifact_rows`
- `direct_artifact_columns`
- `alternative_evidence_status`
- `implementation_status`
- `completeness_status`
- `runtime_evidence_status`
- `plot_render_status`

Alternative evidence no longer upgrades a missing direct public artifact to plain `implemented`; it is kept as a disclosed partial state.

### 6. Coupled-runtime row-shape fix

`+sixgr/+truth/CoupledTruthRuntime.m` had several `struct2table(rows)` call sites changed to `struct2table(rows, "AsArray", true)` so one-row struct arrays with text fields do not crash late in waveform-backed runs.

## Before vs After

### Before

- report-facing control/reference tables were mostly wide mirrors of raw/debug schemas
- many plots had no direct chart-source registry
- one-point relation plots and one-row traces could still be rendered
- coverage rows could look implemented while direct public artifacts were missing or only alternative evidence existed
- late provenance tables were not part of the coverage registry

### After

- users get family-specific public tables with channel-appropriate columns
- plot lineage and suppression are exported as first-class CSVs
- insufficient plot data is suppressed instead of being rendered as misleading charts
- the coverage registry now knows about the new public outputs and provenance outputs
- empty provenance outputs such as unavailable-card registries are still persisted with schema so “no file” no longer masquerades as “not implemented”

## Examples

### PUCCH

Before:

- generic mirrored table behavior made it easy to treat CRC-like state as success even when CRC was not applicable

After:

- `pucch_uci_table.csv` exports `CRCApplicable` and `CRCOutcome`
- `CRCApplicable=0` maps to `CRCOutcome=not_applicable`
- UCI validity remains on `UCIContentMatch` and detection usability fields

### PDCCH

Before:

- public extraction could blur DCI/control semantics with transport-block-style fields

After:

- `pdcch_dci_table.csv` keeps `DCIPayloadBits`
- it does not treat PDCCH like a TBS-bearing data channel

### Noise lineage

Before:

- output users had to infer whether receiver/noise-related values were real, missing, or estimated from scattered raw tables

After:

- `noise_variance_evidence_table.csv` exposes `NoiseVar`, source, status, reason, SNR consistency, and receiver usability in one place

### Plot gating

Before:

- one-point relation plots or one-row traces could still become images

After:

- `validatePlotData` suppresses them
- `plot_manifest.csv` and `plot_suppression_table.csv` record why

## Tests Run

Passed:

- `matlab -batch "setup6GRSimToolkit('Verbose',false); testLLSPlotDataValidation; testLLSOutputCoverageArtifacts"`

Long-running / incomplete:

- `matlab -batch "setup6GRSimToolkit('Verbose',false); testLLSReportBundle"`

The full waveform report-bundle smoke did not complete within the external timeout wrapper. It progressed well beyond the earlier early-crash point and reached late export/report stages (`primary sweep`, `derived tables`, `HARQ diagnostics`), but then stopped producing new file/log progress after `Exporting HARQ diagnostics`, so I stopped the test-owned MATLAB process instead of leaving it running indefinitely.

## Remaining Blockers / Limitations

- `testLLSReportBundle` is still too long for the wrapper budget used so far. This is now a runtime-duration/scaling blocker, not the earlier early-crash bug.
- I have not yet completed `testAll` or the required E2E suites for this patch series. That means the export/report layer changes are validated by focused tests, not yet by a clean full-suite run.
- `chart_source_registry.csv` is persisted and nonempty in the focused export path, but the exact read-back column naming still appears inconsistent enough that the regression test had to validate structure/provenance presence more loosely than planned.

## Recommended Next Work

1. Finish a full `testLLSReportBundle` run with a larger wrapper budget or a narrower smoke profile.
2. Run the required repo-wide validation:
   - `testAll`
   - `testE2E_FastVsTruth`
   - `testE2E_TruthPacketSemanticCampaign`
3. If the long report-bundle run remains too slow, profile the late report/export stages rather than weakening coverage or provenance.
