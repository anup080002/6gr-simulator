# TDD 12 dB CSI measurement availability repair — 15 Sep 2026

## Root cause

A retained slot-31 DL row in the failed 12 dB run has `MeasuredCSIRSRPRelative_dB=NaN`, but `MeasuredCSIRSRPSource=actual_csirs_re_measurement_relative_to_unit_occupied_re_es` and `MeasuredCSIRSRPPhysicalStatus=available_normalized_fixed_esn0_not_absolute_dbm`.

The receiver's old `localRelabelNormalizedCSIRSPower` overwrote source/status unconditionally whenever fixed-reference Es/N0 mode was enabled. Unit conversion is not evidence that a CSI resource was measured. This can promote `not_attempted` or an unavailable selected resource to an available claim without a value.

## Changes

- `+sixgr/+phy/+refsig/normalizeCSIRSPowerReference.m` owns the extracted conversion. It preserves unavailable status/source and only relabels a selected-resource measurement whose producer says available and whose RSRP is finite.
- `+sixgr/+phy/+dl/PDSCH_Rx.m` calls that helper at the same point, after resource selection.
- An explicit conversion marker prevents accidental repeated conversion. Preallocated relative fields containing NaN are not treated as proof of prior conversion.
- Relative numeric values, RSRQ, waveform generation, power/noise scaling and detector thresholds are unchanged. Absolute dBm claims remain unavailable in normalized-reference mode. Physical-power mode is returned unchanged.
- Two named regressions are registered in `testAll`. The existing actual DL measurement fixture now checks both CSI-present and CSI-absent reception, and exposes a failed trial's original diagnostic before indexing an empty CSI table.

## Executed evidence

Unmodified conversion reproduced the false availability claim in `logs/csirs_availability_before_repair_20260915.log`.

Development verification retained two unsuccessful attempts: a mistyped test name ran no tests; an overly broad new duplicate-conversion check rejected the real receiver's preallocated NaN fields. That check was corrected to use explicit conversion state, and the preallocation shape was added to the unit test. No acceptance criterion or measured numeric value was relaxed.

Final focused MATLAB R2026a batch: **5/5 PASS**, `logs/csirs_availability_final_focused_20260915.log`:

- `testNormalizedCSIRSPowerAuthority`: 0.11 s.
- `testNormalizedCSIRSReceiveAvailability`: 82.69 s; actual DL waveform reception with and without CSI-RS.
- `testCSIRSPhysicalResourceMeasurements`: 0.87 s; analytic RSRP/RSSI/RSRQ resource-window checks using generated NR reference grids.
- `testCSIRSBranchMeasurementSelection`: 0.03 s; explicit analytical branch-record fixtures.
- `testNormalizedSSBPowerAuthority`: 43.95 s; existing power-authority guards.

## Remaining qualification

The live `tdd_5mhz_12db_471334ff_20260915` run stays on its frozen 471334ff source and does not contain this repair. Do not patch its running checkout or rewrite its original raw evidence to claim it ran newer code. The repair is a descendant candidate for the same integration branch, not qualified main.

Full final-source `testAll` and required config/LLS/strict/scheduler/export/E2E guards remain outstanding. Existing queued 471334ff tests do not qualify this new revision. No complete measurement/scaling, detector statistical, combined HARQ/CSI/SR or integrated 12 dB acceptance claim is made. The later failed-recovery terminal plot/status fixed-point error remains open.
