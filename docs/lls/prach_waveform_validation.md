# Strict PRACH Waveform Validation

This note documents the `AUD-PRACH-001` repair scope. It is an NR baseline/study
LLS validation profile, not a normative 6G conformance claim.

## Implemented Profile

- Scenario: `configs/lls/lls_prach_strict_mini_anchor.yaml`
- Runner profile: `prach_strict_validation`
- Duplex/frequency profile: FR1 FDD anchor
- PRACH format: long-sequence format `0`
- PRACH source: resolved YAML `random_access` fields
- Supported restricted sets for this anchor: `UnrestrictedSet`,
  `RestrictedSetTypeA`, and `RestrictedSetTypeB`
- Unsupported combinations, including restricted-set short-sequence formats,
  fail closed instead of substituting another format.

## Validation Flow

1. `sixgr.phy.prach.buildPRACHConfigFromScenario` requires explicit strict
   PRACH fields in the resolved scenario config, including `n_cell_id`, SNR
   sweep, timing-offset sweep, and frequency-offset sweep.
2. `sixgr.rach.PRACHConfig` builds `nrCarrierConfig` and `nrPRACHConfig`, then
   validates ZCZ/N_CS before PRACH occasion materialization can hide invalid
   restricted-set combinations behind a later error.
3. `sixgr.phy.prach.generatePRACHWaveform` emits real baseband PRACH samples and
   a SHA-256 waveform hash.
4. `sixgr.phy.prach.detectPRACHWaveform` consumes received waveform samples and
   receiver configuration only.
5. `sixgr.phy.prach.scorePRACHDetection` scores positive and negative evidence
   after detection. It does not allow negative or sweep rows to count as strict
   positive success.

## Evidence Artifacts

Strict runs write these primary PRACH artifacts:

- `control/csv/prach_config_strict.csv`
- `control/csv/prach_trials.csv`
- `control/csv/prach_detection_candidates.csv`
- `control/csv/prach_restricted_set_mapping.csv`
- `control/csv/prach_root_sequence_budget.csv`
- `control/csv/prach_zcz_cyclic_shift_mapping.csv`
- `control/csv/prach_missed_detection_sweep.csv`
- `control/csv/prach_false_alarm_sweep.csv`
- `control/csv/prach_timing_offset_sweep.csv`
- `control/csv/prach_frequency_offset_sweep.csv`
- `control/csv/prach_collision_trials.csv`
- `control/csv/prach_multi_occasion_trials.csv`
- `control/csv/prach_negative_trials.csv`
- `control/csv/prach_oracle_guard.csv`
- `reports/json/prach_toolbox_capabilities.json`

Figures are measured PRACH plots only; unavailable-card figures do not satisfy
`AUD-PRACH-001`.

## Truth Gate

`sixgr.truth.evaluateLLSRuntimeTruthContract` marks strict PRACH as successful
only when:

- positive waveform detection passes with matching preamble and timing within
  tolerance,
- no `ProxyUsed`, `Skipped`, or `ToolboxMissing` rows contribute to success,
- oracle guard violations are zero,
- restricted-set, ZCZ, and root-budget tables are non-empty and valid,
- missed-detection and false-alarm sweeps contain measured probability rows,
- timing sweep rows are within tolerance for the supported in-window offsets,
- frequency-offset, collision, multi-occasion, and negative wrong-config evidence
  is present and measured,
- old simplified PRACH success markers are absent.

## Known Limitations

- This is not exhaustive PRACH coverage for every NR release format.
- FR2, SUL, NTN, RedCap, HST, and all short-format restricted-set studies remain
  unsupported unless a future patch adds equivalent waveform evidence.
- Early-arrival/window-underflow timing cases are not part of the strict positive
  mini anchor; they should be modeled as explicit negative or extended receiver
  search-window studies.
- Full Msg1-Msg2-Msg3-Msg4 random access is tracked separately from this PRACH
  waveform validation profile.

## Focused Test Commands

```matlab
matlab -softwareopengl -batch "setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false); testPRACHLLS"
```

```powershell
$env:MATLAB_FLAGS='-softwareopengl'
python tools\matlab\run_matlab_test_isolated.py testPRACHConfigStrictValidation testPRACHWaveformGeneration testPRACHWaveformDetectionPositive testPRACHRestrictedSetMapping testPRACHMissedDetectionSweep testPRACHFalseAlarmSweep testPRACHTimingOffsetSweep testPRACHFrequencyOffsetRestrictedSet testPRACHCollisionAndMultiPreamble testPRACHMultiOccasionRARNTI testPRACHNegativeWrongConfig testPRACHOracleGuard testPRACHArtifactSchemas --log-dir reports/logs/matlab/prach_strict_isolated
```
