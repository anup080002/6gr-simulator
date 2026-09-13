# PUCCH receive-only boundary and semantic audit follow-up

This is an incomplete-goal checkpoint following `8cfac549`, not baseline,
detector, Phase-05 or full-suite qualification. Production MATLAB source was
not changed while the two consolidation validation processes were running.

## Verified receiver and runtime boundary

- `PUCCHReceiver.receive` accepts `PUCCHTransmissionAssignment`, whose
  constructor requires both transmit power-control and spatial-relation
  state. There is no typed receive-only assignment in the PUCCH package.
- `runPUCCHWaveformTrial` also requires a report and a transmit assignment;
  its received shared path obtains these from a prepared transmission.
- `scheduledDLHARQExpectation` correctly binds a gNB expectation to a physical
  DL commit without claiming UE control reception. Searching production
  MATLAB sources for `SharedDLHARQExpectations` found its recording path in
  `commitSharedDataTransmission`, but no consumer that schedules an independent
  receive-only feedback observation.
- `testPUCCHBaselineNoiseRF` currently calls `nrPUCCHDecode` directly, not the
  canonical PUCCH receiver. Its noise evidence cannot qualify that missing
  main-runtime receive-only path.

A read-only replay used the first retained observation in
`evidence_20260913/pucch_baseline_noise_rf_01/noise_observations.mat`: 7,680
samples, two receive branches. The Toolbox detector metric was
`0.27998281646636541`, matching the CSV's `0.27998281646636503` within 1e-12.
The canonical API rejected a resource-only struct with a typed length-only
`UCIReportContext` as `sixgr:phy:pucch:WrongResource` (typed assignment required).
This is an API-boundary diagnostic, not a claim that the struct is an accepted
typed assignment or that missed-DCI reception was executed.

Logs are `%TEMP%/sixgr_receive_only_probe_20260913.log` and
`%TEMP%/sixgr_receive_only_probe_20260913_02.log`. The first replay reached the
matching metric but failed due to native-shell quoting of a MATLAB string;
the second completed with exit 0 and reproduced the rejection.

## Retained CSV / PNG checks

Independent CSV aggregation reproduced both 512-occasion summaries:

| HARQ bits | False detections | False ACK bits / available positions | Fraction |
| --- | --- | --- | --- |
| 1 | 8 | 2 / 512 | 0.00390625 |
| 2 | 16 | 12 / 1024 | 0.01171875 |

The two-bit result exceeds this fixture's configured 0.01 reference. The
one-bit empirical fraction is below it, but that alone does not prove
conformance. The existing scope labels and IID-assumption caveat remain.
`noise_detector_audit_verified.png` was visually inspected: the empirical CDF,
0.42 configured threshold and 0.390625% / 1.171875% bars agree with these CSVs;
the chart explicitly says component observation, not conformance qualification.

The retained signal-present row in
`pucch_baseline_signal_04/received_pucch_trials.csv` was parsed by column name.
Its expected and decoded vectors both equal `10`; `FalseAck=0`, `FalseNack=0`
and `BitErrors=0`. An initial visual reading of the wide raw CSV suggested a
contradiction; named-column parsing disproved it. The retained row is not a
newly discovered false-ACK export defect and was not rewritten.

## Auditor change and tests

The production CSV auditor previously did not check HARQ error flags. It now
checks any declared `FalseAck` / `FalseNack` fields for valid boolean values,
rejects asserted errors with identical nonempty binary expected/received UCI,
and rejects asserted decoded errors when the receiver explicitly reports DTX.
It does not turn missing feedback into NACK or infer a payload from empty data.
This check does not replace artifact schema/coverage checks or recompute a full
HARQ codebook, and passing it alone does not qualify an artifact.

Fifteen new tests cover valid observations, corrupted flags, DTX versus NACK,
invalid booleans and the actual retained shared-waveform row with mutations.
Before implementation the original 14 cases failed because the check was
absent. After implementation and the retained-row case were added:

`python -m pytest tests/test_pucch_harq_flag_semantics.py tests/test_lls_csv_semantics.py -q`

Result: **101 passed**. The retained signal-present row passes this check;
changing either error flag to true in test memory fails it.

The unchanged MATLAB consolidation guard batch has passed CSI calendar,
configuration, strict proxy/no-fallback, DL, UL, reference points, link export,
artifact integrity/preservation and scheduler grant consistency. Phase-05
artifact generation failed at the existing `UnverifiedPhaseEvidence` gate.
E2E checks and full `testAll` are still running at this checkpoint; no full
validation PASS is claimed. Their original process handles remain in use.

## Next required implementation

Create a receiver-owned typed PUCCH allocation/context from the gNB's actual
schedule and installed RRC, without UE payload, power or transmit-success
dependencies. Wire scheduled expectations to physical receive windows even
when no UE feedback transmission exists. Exercise that canonical path on the
retained noise and paired signal observations, then qualify false/missed ACK
behavior and Type-2 chronology before the final 58-slot baseline run.
Keep the larger impairment-enabled, configuration-driven 6G/NR and artifact
closure objectives unchanged. The existing Phase-05 quarantine must remain
until all of its missing evidence producers are implemented and verified.
