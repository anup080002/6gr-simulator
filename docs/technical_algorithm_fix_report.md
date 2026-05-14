# Technical Algorithm Fix Report

Date: 2026-04-25

## Scope of this pass

This pass did not complete the full 12-phase standards-repair roadmap. It repaired the concrete runtime and reporting defects that were verified during the latest artifact correlation and LLS-first audit:

- UL control/reference explicit noise-variance handling in `PUCCH_Rx` and `SRS_Rx`
- PUCCH CRC/detection semantics in waveform trial output, coupled runtime control rows, and public extraction/reporting
- PUCCH UCI efficiency reporting so it no longer uses `CRCPass` when CRC is not applicable

## Latest bundle correlation used for triage

Audited bundle:

- `results/lls/lls_report_bundle/smoke`

Observed before this patch:

- Bundle incomplete/stalled after `Exporting HARQ diagnostics.`
- `reports/csv/plot_manifest.csv` missing
- `reports/csv/output_coverage_registry.csv` missing
- `air_interface/csv/pucch_trials.csv` had 569 rows with `CRCApplicable=0` and `CRCPass=1`
- `air_interface/csv/pucch_trials.csv` also showed many extremely small exported `NoiseVariance` values sourced as runtime metadata

## Files changed

- `+sixgr/+phy/+ul/PUCCH_Rx.m`
- `+sixgr/+phy/+ul/SRS_Rx.m`
- `+sixgr/+link/runPUCCHWaveformTrial.m`
- `+sixgr/+truth/CoupledTruthRuntime.m`
- `+sixgr/+truth/runWaveformLinkBundle.m`
- `+sixgr/+truth/buildLLSPublicOutputTables.m`
- `+sixgr/+truth/exportLLSReportingBundle.m`
- `+sixgr/+truth/llsOutputContract.m`
- `tests/testLLSPUCCHWaveformFeedback.m`
- `tests/testULNoiseVarianceValidation.m`

## Before

- `PUCCH_Rx` and `SRS_Rx` accepted explicit `NoiseVar` without converting waveform-domain AWGN variance into the OFDM/grid domain used downstream.
- Raw/runtime-backed PUCCH rows could export `CRCPass=1` even when `CRCApplicable=0`.
- PUCCH reporting paths still used `CRCPass` as a UCI success signal.
- Public PUCCH extraction did not expose a dedicated `DetectionOutcome`.

## After

- `PUCCH_Rx` and `SRS_Rx` now convert explicit/configured noise variance into the grid domain before validation and use.
- PUCCH waveform output now exports explicit `CRCOutcome` and `DetectionOutcome`.
- Coupled-runtime and bundle-level raw PUCCH rows now keep `CRCPass=NaN` when `CRCApplicable=0`.
- Public PUCCH extraction now exposes `DetectionOutcome` alongside `CRCOutcome`.
- UCI efficiency reporting now uses `UCIContentMatch` first, then `CRCOutcome`, and only falls back to `CRCPass` when CRC actually applies.

## 3GPP anchors

- TS 38.213: PUCCH/UCI control procedure semantics
- TS 38.214: link adaptation and runtime decision semantics
- TS 38.215: receiver measurement observability and noise/SINR evidence roles

## Tests run

Passed:

- `matlab -batch "setup6GRSimToolkit('Verbose',false); testULNoiseVarianceValidation; testLLSPUCCHWaveformFeedback; testLLSOutputCoverageArtifacts"`
- `matlab -batch "setup6GRSimToolkit('Verbose',false); testConfig; testLLS_DL; testLLS_UL; testLLS_ReferencePoints; testE2E_FastVsTruth; testE2E_TruthPacketSemanticCampaign"`

Timed out and was stopped cleanly:

- `matlab -batch "setup6GRSimToolkit('Verbose',false); testAll"`

## Remaining limitations

- The audited `results/lls/lls_report_bundle/smoke` bundle predates this patch and still contains the old PUCCH CRC misuse. It must be rerun to regenerate corrected artifacts.
- This pass did not finish the broader scenario/channel, TBS/LDPC, plot-manifest regeneration, or browser-binding roadmap items from the 12-phase request.
- Full repo-wide `testAll` still exceeds the current 4-hour execution window in this environment.
