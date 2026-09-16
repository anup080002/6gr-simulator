# TDD normalized SSB-window RSRQ evidence preservation

Status: focused validation passed; full-suite, integrated execution and all-measurement acceptance remain pending. This repair follows `a1c9a92904813b394d59d8e7019858886a11cc77` and is not in the running `d05c1441` 12 dB scenario.

## Root cause and scope

`measureSSBWindowPower` produces actual per-antenna reference RSRP, RSSI and RSRQ with 20 RB / 240 subcarrier / four-symbol window metadata. `recoverSIB1FromWaveform` retains that evidence. `normalizeReceivedSSBPowerReference` previously discarded the entire physical-unit JSON in fixed-reference sweeps. Clearing invalid absolute-unit claims was correct, but also discarded dimensionless RSRQ and the window/branch provenance.

The repair converts only dimensional power operands into the existing unit-occupied-RE reference plane and preserves the measured RSRQ. It checks `RSRQ_dB = 10*log10(NumRB) + reference_RSRP_dB - RSSI_dB` using matching per-branch operands. It retains symbol/RB/branch scope and labels the reference estimator separately from the primary noise-debiased SSS RSRP. Missing window evidence remains missing. Malformed evidence or inconsistent RSRQ operands fail; no fallback measurement is generated.

This is explicitly an SSB-window reference measurement, **not** an unrestricted full-carrier NR RSSI/RSRQ report. No waveform, noise, gain, decoder, ACK, SINR, or acceptance threshold is changed. Physical-mode records are unchanged except for additional explicitly scoped reference-RSRQ export fields.

## Changed surfaces

- `+sixgr/+link/normalizeReceivedSSBPowerReference.m`: preserve normalized window JSON and dimensionless RSRQ with operand checks.
- `+sixgr/+link/ssbPowerReferenceEvidence.m`: propagate the typed evidence to existing result adapters.
- `+sixgr/+phy/+broadcast/recoverSIB1FromWaveform.m`: initialize/export actual window RSRQ and scope, maintaining compatible success/failure record shapes.
- Four existing test files: independent scale/ratio checks, malformed evidence rejection, acquisition and periodic-delivery CSV round trips. Original power-authority and physical-unit exclusion assertions remain.

## Retained test evidence

Command, MATLAB R2026a, terminal exit **0**:

```matlab
setup6GRSimToolkit('Verbose',false);
r=runFocusedTests({'testNormalizedSSBPowerMath','testNormalizedSSBPowerAuthority', ...
 'testNormalizedSSBBroadcastPower','testNormalizedSSBOccasionDelivery','testSSBWindowPower'});
assert(r.ok,'SSB window RSRQ preservation validation failed');
```

All five tests passed. The authority test is a declared power-domain unit fixture, not an RF episode; broadcast and occasion-delivery tests exercise actual reception and persisted CSV evidence.

Log: `logs/ssb_window_rsrq_preservation_v2_20260916.log`

SHA-256: `FF06F292294B5E9A8BFE3F397C7CEE3980AC8E25CC5A67CDE8834FB7F9ED7392`

The earlier log `logs/ssb_window_rsrq_preservation_20260916.log` is retained: four passes and one authority-fixture failure. Its old dummy JSON lacked the newly required window schema. The positive unit fixture now supplies an explicitly declared complete window; the old malformed JSON is retained as a negative rejection test. No original assertion was removed.

## Remaining acceptance

Run `testAll`, NR/config/strict/scheduler guards, export/artifact guards, and both E2E truth/proxy guards on one frozen final revision. Run the 5 MHz TDD / 12 dB integration on the consolidated revision and audit its exported measurements. Detector false/missed-ACK qualification, other regression failures, full-carrier report-window coverage, PNG review and MATLAB R2023b validation are separate unfinished requirements. These focused results do not establish overall 3GPP conformance or acceptance.
