# Strict PDCCH Blind Detection

This page documents the `AUD-PDCCH-001` repair for the NR-baseline/study strict
PDCCH mini profile. It is not a normative 6G conformance claim.

## Implemented Profile

- Scenario: `configs/lls/lls_pdcch_strict_mini_anchor.yaml`
- Runner profile: `pdcch_strict_validation`
- Supported DCI formats in the strict mini profile: `1_0` and `0_0`
- Supported strict RNTI profile: `C-RNTI`
- Supported CORESET/search-space profile: explicit scenario-configured FR1
  CORESET and UE search space using 5G Toolbox PDCCH resources
- Physical path: `nrDCIEncode`, `nrPDCCHResources`, `nrPDCCH`,
  `nrPDCCHDecode`, `nrDCIDecode`, OFDM modulation/demodulation, and DM-RS aided
  channel estimation through the repository PDCCH Tx/Rx wrappers

## Receiver No-Oracle Rule

The receiver receives waveform samples plus allowed carrier, CORESET,
search-space, monitored RNTI, DCI format, and noise-variance context. It must
not read transmitted DCI bits, transmitted payload hex, transmitted selected
candidate, transmitted aggregation level, transmitted CCE index, or a scheduler
grant before blind decode. The strict runner exports `pdcch_oracle_guard.csv`
and the truth contract fails if any forbidden field is accessed.

## Evidence Exported

- `control/csv/pdcch_config_strict.csv`
- `control/csv/pdcch_trials.csv`
- `control/csv/pdcch_candidates.csv`
- `control/csv/pdcch_dci_fields.csv`
- `control/csv/pdcch_grant_validation.csv`
- `control/csv/pdcch_wrong_rnti_trials.csv`
- `control/csv/pdcch_no_signal_trials.csv`
- `control/csv/pdcch_corruption_trials.csv`
- `control/csv/pdcch_false_alarm_sweep.csv`
- `control/csv/pdcch_low_snr_sweep.csv`
- `control/csv/pdcch_oracle_guard.csv`
- `air_interface/csv/pdcch_trials.csv`
- `reports/json/pdcch_*`
- `reports/figures/pdcch_*`

## Negative Evidence

The strict mini profile includes wrong-RNTI, no-signal/noise-only, corrupted
PDCCH data RE, corrupted PDCCH DM-RS, wrong DCI format, and invalid grant-field
trials. Negative trials use `NegativeExpectedOk=true`; they must never set
`StrictOk=true`.

## Truth Gate

`+sixgr/+truth/evaluateLLSRuntimeTruthContract.m` requires the strict PDCCH CSV
and JSON artifacts for `pdcch_strict_validation`. It rejects proxy/skipped/toolbox
missing rows, oracle use, missing negative evidence, missing DCI/grant evidence,
and old all-success `DetectionMetric=1` rows without candidate metric evidence.

## Focused Tests

Run with MATLAB R2024a:

```powershell
$env:MATLAB_FLAGS='-softwareopengl'
python tools/matlab/run_matlab_test_isolated.py tests/testPDCCHConfigStrictValidation.m tests/testPDCCHWaveformGeneration.m tests/testPDCCHBlindDecodePositiveDCI10.m tests/testPDCCHBlindDecodePositiveDCI00.m tests/testPDCCHWrongRNTIReject.m tests/testPDCCHNoSignalFalseAlarm.m tests/testPDCCHCorruptedPDCCHReject.m tests/testPDCCHCandidateBlindSearch.m tests/testPDCCHWrongDCIFormatReject.m tests/testPDCCHInvalidGrantReject.m tests/testPDCCHFalseAlarmSweep.m tests/testPDCCHLowSNRSweep.m tests/testPDCCHOracleGuard.m tests/testPDCCHArtifactSchemas.m tests/testPDCCHGrantReferencePropagation.m
```

## Known Limitations

- DCI `1_1` and `0_1` are fail-closed for this strict mini profile.
- SI-RNTI, RA-RNTI, TC-RNTI, P-RNTI, and other special RNTI integrations are not
  claimed closed by `AUD-PDCCH-001`.
- Multi-BWP, cross-carrier scheduling, beam-specific PDCCH, Rel-17/18/19/20
  enhancements, and full SIB1/RA downstream integration remain separate work.
