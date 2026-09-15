# TDD 5 MHz / 12 dB: SSB clock and power-reference repair

This is an unqualified integration checkpoint, not an accepted 12 dB run.
The user priority remains the exact normalized 5 MHz TDD diagnostic. FDD and
400 MHz implementation remain deferred; the full goal and sweep are unchanged.

## Authoritative completed runs

Revision 5689ed332afdeeccd30f4721862d6f5e25e439ff:

- Integrated run tdd_5mhz_12db_5689ed33_20260915 passed allocation preflight,
  acquired the cell and reached slot 22. It then failed with
  sixgr:phy:refsig:InvalidMeasurementClockDomain before any connected DL/UL
  data rows. The error originated in SSB consumption by
  bindSharedSSBPowerReference. It is not a successful 12 dB result.
- Failed-run report recovery additionally failed with
  sixgr:truth:recover:TerminalArtifactFixedPointFailed. Plot-source hash and
  terminal-status convergence remains a separate open result-integrity issue.
- Clean frozen-source testAll ran to completion: 689 tests, 46 failed,
  643 passed, 21379.59 seconds. Validation checkout log:
  logs/testall_20260915T024538145Z_11e6d44c. The sibling ZIP and originals
  remain preserved. See testall_5689ed33_failures_20260915.csv for the complete
  failure-name/identifier inventory; full messages remain in failures.csv
  and test_report.json in the original log.
- The following guard batch did NOT execute assertions: it requested the
  nonexistent selftest6GRSimToolkit. Its launcher failure is preserved at
  logs/testall_20260915T084518382Z_866d79e7 in the validation checkout.
  Rerun the real named guards without this invalid launcher entry.

## Root cause and implemented changes

SSBOccasionResultDelivery.deliver previously published a slot_only row and
then manually attached three sample-window columns. The consumer correctly
rejected that contradictory row; completion sample and clock epoch were
absent. Do not remove or weaken the consumer's clock-domain guard.

1. SSBOccasionResultDelivery.complete retains actual completion sample and
   physical epoch. bindSharedReferenceDeliveryClock binds publication to the
   real owner's canonical slot-start sample and exact OFDM boundaries,
   rejecting future completion, mismatched epochs and clock rebinding.
2. Publication carries complete sample evidence before it reaches consumers.
   Full shared PBCH acquisition now retains the same completion/epoch fields
   and crosses that delivery boundary through BroadcastResultDelivery.
   Explicit legacy unit fixtures remain unclocked, not relabeled shared RF.
3. Per-occasion SSB recovery also bypassed the existing normalized-power
   labeling used by full-burst completion. Both now use
   normalizeReceivedSSBPowerReference. Relative RSRP/RSSI remains available
   in explicitly relative units; arbitrary normalized samples are not
   emitted as antenna-connector dBm or used to manufacture pathloss.
4. The measurement ledger retains relative RSRP. Decoded normalized SSB
   measurements remain valid for their measured quantities, while the
   absolute-dBm UE filter rejects inconsistent labels and does not consume
   relative powers. No RF sample, decoder threshold or noise/power target
   was changed by this repair.
5. The physical per-SSB delivery test was absent from testAll. Both its
   physical-power and normalized-SNR variants are now registered. A missing
   ServingCell in the declared broadcast-delivery fixture was repaired.

## Executed focused evidence, MATLAB R2026a Update 4

Each test ran on unchanged dirty source based on 5689ed33. These are component
results, not clean final-source or integrated qualification.

- logs/testall_20260915T134527184Z_c1371a56:
  testCausalMeasurementSampleClock and testCSIMixedClockConsumer PASS.
  Other failures in that attempt are retained.
- logs/testall_20260915T135014151Z_18f075d8:
  testBroadcastResultDelivery PASS (23.75 s),
  testNormalizedSSBPowerAuthority PASS (11.22 s),
  testSSBPowerReferenceContract PASS (35.47 s).
  Physical companion/input and diagnostic-directory failures are preserved.
- logs/testall_20260915T135333816Z_8203bcb7:
  testNormalizedSSBOccasionDelivery PASS (29.34 s), four actual SSBs,
  earliest publication slot 2, exact sample-clock consumption, no duplicate
  TX/filter, relative power/CSV checks. Raw evidence:
  logs/tp16b23ffa_c146_4c66_b813_90788d33f4f3.
  testSharedSSBOccasionDelivery remains FAIL (44.21 s).

## Open physical-power companion failure

The companion uses the existing physical-power YAML fixture and a declared
codec SIB1 fixture matching the prepared TX's 5 dBm SSS declaration. At the
first delivery it measures 5.1798 dBm for SSB 0. Subtraction yields negative
estimated pathloss; the unchanged physical pathloss guard rejects it.
SSB 1 measures -0.51614 dBm. Raw data:
logs/tpd4582c37_8c84_498d_be27_3411748170ea/first_delivery_measurements.mat.

Do not clamp the estimate, adjust power/noise to pass, suppress the test, or
claim this companion qualified. Its channel/power-reference/measurement
accounting needs further diagnosis. The normalized 12 dB scenario explicitly
does not use this absolute pathloss estimate and retains its original config.

## Next work, not yet completed

Rerun the exact 58-slot normalized 12 dB scenario on the new clean checkpoint.
Inspect passage through slot 22, random access, received CSI/SRS and shared
HARQ through actual PUCCH/PUSCH, then data, measurements and artifacts.
Run current-source testAll plus required NR/config, scheduler, strict-proxy,
export and E2E guards. Close all 46 inventoried failures and any new failures;
do not treat registration or queueing as a pass. Original PUCCH false-ACK/
missed-ACK qualification, combined HARQ/CSI/SR coverage, final measurement/
CSV/PNG closure, patch reconciliation and qualified-main promotion remain open.
