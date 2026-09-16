# DL receiver SINR diagnostics: primary-table handoff

Status: focused tests passed; full-suite and final integrated acceptance pending. Parent revision: `3258e469055bd5101106ebfb1a8843ffa2abba4d`. The live 5 MHz / 12 dB run remains on unchanged `d05c1441`.

## Root cause

Actual `d05c1441` DL rows contain `PostEqSINRValueStatus=OK_DECISION_RESIDUAL_BOUNDED` but omit the raw equalizer and residual-bound operands. `+sixgr/+phy/+dl/PDSCH_Rx.m` already computes these fields from the canonical receiver. `+sixgr/+link/runDLPDSCHThroughput.m` copied the selected result/status but not the diagnostic fields to its accumulated/empty trial schema. UL already retained some analogous fields.

## Repair

The DL primary trial table now retains the receiver-produced raw scalar and per-layer equalizer SINR, DMRS and decision-residual values, bound-enabled flags and actually-applied flags. No receiver algorithm, waveform, power/noise, scheduler value, CRC result or qualification threshold changes. Missing numeric diagnostics remain NaN; no operands are inferred from EVM or configured SNR.

The raw per-layer vector is explicitly bracketed, uses 17-digit formatting and retains missing coordinates. Brackets prevent a one-layer vector becoming an inferred scalar CSV column.

## Tests and limits

MATLAB R2026a command, terminal exit **0**:

```matlab
setup6GRSimToolkit('Verbose',false);
r=runFocusedTests({'testNormalizedCSIRSReceiveAvailability', ...
 'testPDSCHReceiverMIMONoiseDomain','testNoiseDomainEvidenceContract'});
assert(r.ok,'DL receiver SINR export validation failed');
```

All three tests passed. Existing CSI-present and CSI-absent actual DL receiver fixtures now verify the new primary-table fields, one-layer operand closure and flag/status consistency. Their bit-exact file guard explicitly requests the existing `RoundTripNumericText=true` CSV option. This does **not** claim that every default/display CSV is bit-exact. The MIMO receiver companion retains its independent equalizer-weight and deliberately data-distorted residual-bound checks. The receiver algorithm itself was not changed.

Log: `logs/dl_receiver_sinr_export_v3_20260916.log`

SHA-256: `F79F926203A9F5DF09C4EE7F450949A4EB45B64BA4CADC3F187379F9CD558432`

Earlier logs are preserved: v1 failed the unbracketed scalar/vector CSV type comparison; v2 reached both actual receive fixtures but failed the bit-exact comparison with the default display-precision writer. The vector serialization was corrected and the existing exact numeric serialization option selected. Assertions were retained; no original receiver or CSI assertion was removed.

These isolated receive fixtures are not the integrated TDD 12 dB acceptance result. Required `testAll`, NR/strict/scheduler, export/artifact and E2E guards remain to be run on the final consolidated source. The unstarted combined-validation helper 6120 was retired before MATLAB execution so this and the next related measurement repair can be validated together; its logs/status remain in `logs/combined_measurement_final_validation_20260916`. Current live scenario/validation helper 12972 was not stopped.

## Independently retained integrated evidence

Separate immutable snapshots from the live `d05c1441` run passed 88 full-allocation paired-symbol EVM checks across seven DL and one UL transmission. A diagnostic preview produced 12 PNGs and passed 352 checks on artifact hashes and plotted EVM/throughput operands. Those checks do not qualify every measurement or the final run.

The subsequent visual review found another real issue: `+sixgr/+truth/measureReceivedDataCarrierPower.m` unconditionally labels the data-window FFT powers as physical watts/dBm even when `prepared.InputConfig` selects normalized fixed-reference operation. `apps/lls_radio_measurement_plots.py::_data_carrier_power` carries those labels into PNGs. Correcting the producer reference plane and both DL/UL plot/export units, without modifying physical samples, is the next required repair. The historical CSV/PNG evidence is preserved, not relabeled retroactively as correct.
