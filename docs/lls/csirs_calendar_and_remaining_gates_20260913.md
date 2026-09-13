# CSI-RS calendar repair and baseline readiness

The final 58-slot 12 dB simulation remains **held**, not qualified. This
checkpoint follows [the gNB feedback repair](gnb_feedback_expectation_20260913.md).
It does not change the configured SINR, duplex pattern, channel, RF settings,
SRS/PUSCH ports or waveform execution backend.

Follow-up: [clock fixture correction and constellation publication](csi_clock_fixture_and_constellation_publication_20260913.md)
narrows and closes the reproduced HARQ alias mismatch as a fixture error,
with the complete CSI runtime regression passing. The planner failure below
remains unresolved; historical failed receipts have not been overwritten.

## Reproduced cause and implementation

`sixgr.phy.refsig.csirs` previously returned an always-active Toolbox resource
(`CSIRSPeriod='on'`). The PDSCH transmitter checked the configured occasion,
but the independent received-DCI allocator and planned-grid resolver could
reserve/materialize that resource on slots without a CSI-RS transmission.

The shared generator now validates the absolute carrier/config clock, reads
the existing YAML-derived period/offset and retains that calendar in the
returned Toolbox resource. The indices/symbols must agree with the calendar;
enabled is distinct from scheduled. Resource definitions remain available on
inactive slots for future-slot planning, but no RE/symbol rows are invented.
Multi-resource configuration is validated even on inactive slots. Explicit
Toolbox-object callers retain their supplied configuration. Existing explicit
every-slot test fixtures use the Toolbox `on` representation; this is not a
claim of a new NR periodicity. Mapping fixtures now declare their own calendar
instead of relying on a hidden always-on generator.

The NR candidate-slot relation is `(slots_per_frame * frame + slot - offset)
mod period == 0`; see [TS 38.211 v18.8.0, 7.4.1.5.3](https://www.etsi.org/deliver/etsi_ts/138200_138299/138211/18.08.00_60/ts_138211v180800p.pdf).
The Toolbox representation is documented in [nrCSIRSConfig](https://www.mathworks.com/help/5g/ref/nrcsirsconfig.html).
The config-driven and result-integrity skills guided retaining YAML authority
and separating configured resources from actual transmission evidence.

The retained received-DCI assignment is at absolute slot 62 (a component
capture, not a new slot in the 58-slot baseline). With the baseline calendar
`5:1`, it is inactive. The corrected allocation has zero extra reserved REs,
G=3108 bits and TBS=1064 bits with CSI enabled or disabled. Previously the
enabled path removed 12 REs and reduced G to 3060. No received samples or
historical run files were reconstructed or overwritten.

## Focused test receipts

- `evidence_20260913/csirs_calendar_tests_01.txt`: exit 1, new explicit-object
  test fixture incorrectly requested the Toolbox default 52 RBs on a 25-RB
  carrier. Corrected the fixture to the carrier size; no production clamp.
- `evidence_20260913/csirs_calendar_tests_02.txt`: exit 0. Generator calendar,
  frame-boundary/clock guards, retained-DCI non-occasion capacity, exact active
  reservations/collision guard, multi-resource and port/row authority passed.
- `evidence_20260913/csirs_calendar_estimator_regressions_01.txt`: exit 0.
  `testChannelEstimateOraclePath`, `testReferenceSignalCausalProducersConsumers`
  and `testCSIRSOracleValidationCampaign` passed. Oracle diagnostics remain
  test-only; practical estimates do not consume the known channel.
- `evidence_20260913/csirs_calendar_integration_01.txt`: exit 1. A separate
  planner API bug treats a character-array `TargetChannels` argument as
  individual characters. The accepted string-selector path is under test in
  `_02`. The baseline uses the default invocation, not that char selector.
  The char-selector defect remains open; changing this test's argument type
  is not presented as repairing the API.
- `evidence_20260913/csirs_calendar_integration_02.txt`: exit 1. With the
  correct selector, planning reaches an inactive CSI occasion but unconditionally
  calls the exact-allocation materializer, which correctly rejects empty REs.
  The planner must skip inactive occasions before materialization. Previously
  its all-slot resource fabricated planned CSI occupancy instead. The required
  planner patch is preserved in `pending_csirs_planner_calendar.patch` but is
  **not applied or tested**, because the source editor refuses the target file.
  The generator repair is therefore only a partial, unqualified integration:
  **current full-run planning fails closed and this revision must not be run
  as the final baseline**. The materializer's nonempty-allocation invariant is
  not weakened to hide this caller defect.
- `evidence_20260913/csirs_calendar_runtime_regressions_01.txt`: exit 1.
  `testConnectedTRSResourceSharing` and `testBaselineSpecialSlotScheduler`
  passed: received-DCI special-slot TRS allocation has 36 reserved REs,
  G=1836 versus 1980 without TRS, and main-created scheduler grants exist at
  slots 3 and 8 with TDRA 1 / [2,8]. The later `testCSIRuntimeExecution`
  reaches `HARQExecutedClockMismatch` before its strict non-occasion result
  can be qualified. Its manually constructed scheduler grant carries
  zero-based `Frame`/`Slot`; `localBuildHARQGrantSnapshot` preserves those
  aliases, but `bindExecutedHARQClock` requires one-based execution aliases.
  The separate `resolveWaveformGrant` adapter already documents the
  zero-based control versus one-based execution distinction. Repair must
  establish the correct boundary contract, preserve canonical timing and
  immutable grant identity, and retain mismatch guards, not blindly add one
  inside the binder. Whether this exact fixture entry path affects the main
  baseline still needs tracing. No full CSI runtime PASS is claimed.

No `testAll`, E2E campaign or full 58-slot scenario was launched. These are
focused checks under the user's explicit test scope, not full-suite approval.

## Editor/Git finding

Source patches to `PUCCHReceiver.m` and `buildPlannedREAllocation.m` still
return `Failed to write file`; the previous allocator failure is also not
resolved as an editor problem. Ordinary tracked-file status, no special Git
attributes, no index lock, non-read-only attributes, visible modification ACLs
and sufficient free disk space do not establish Git/GitHub as the cause.
The same installed patch engine reproduced the planner failure. No ACL change,
alternate source writer, deletion or replacement was used. The CSI repair is
in the shared resource generator. Its returned periodic configuration fixes
the allocator's inactive-slot capacity, but the planner still needs the
unapplied companion patch described above.

## Access and special-slot status

The retained run's zero-based sequence is PBCH available 5, PRACH 14, RAR 16,
Msg3 19, Msg4 22, RRC complete 24, SRS 29, data PDSCH 30. Configured access
occasions and the measured-SRS prerequisite explain the wait; it is not CPU
processing time or a universal 30-slot access requirement. Missing RA grid
producers also make some occupied slots look empty. See the
[retained-run audit](continuous_iq_02_access_artifact_reaudit_20260913.md).

Special-slot causes already repaired in focused tests: the old [2,12] PDSCH
did not fit ten DL symbols, and sparse TRS was excluding entire PRBs. The
configured [2,8] TDRA and exact TRS RE reservation admit grants in special
slots 3 and 8. Actual complete shared-stream data/feedback qualification is
still required. See [the scheduler checkpoint](special_slot_scheduler_trs_20260913.md).

## Remaining gates, in order

1. Restore reliable source editing and apply/test the CSI planner companion
   patch (including both selector types); repair receiver-only PUCCH context,
   Format-0 HARQ/SR semantics and false-ACK/missed-ACK detector qualification.
2. Complete missed-DL-DCI reception/disposition, dynamic Type-2 HARQ-ACK DAI
   ordering/wrap/missing positions and shared feedback chronology. The gNB
   expectation producer and reservation-transfer guards are not that receiver.
   Resolve the newly reproduced scheduler-grant/executed-HARQ clock-domain
   mismatch and rerun the complete CSI runtime regression as well.
3. Qualify actual special-slot PDCCH/PDSCH/PUCCH execution, TA/TAG/NTA offsets,
   DL/UL synchronization, propagation/filter delays and capture origins with
   deliberate timing perturbations.
4. Close SS/CSI/PDSCH/PUSCH SINR and all-channel RSSI/EVM/power measurement equations against
   actual powers, noise domains and complex weights. Measurement naming and
   component tests do not prove all values correct; no arbitrary gap removal.
   Include PRACH detection/threshold margins, PUCCH UCI outcomes and SRS
   measurement domains, not only downlink data and reference-signal summaries.
5. Prove measured two-port UL TPMI, PMI basis, QCL/TCI consumption and AMC
   feedback causality in this baseline. Approved two-port SRS/PUSCH, rank one,
   remain in the actual continuous-IQ 12 dB YAML, not an unused extra profile.
6. Complete RA/grid/beam/constellation PNG producers, alignment CSV columns,
   snapshot contracts, canonical artifact discovery and repeat-safe rendering.
   Close the newly found character-array planner-selector API defect as well.
7. Run one final 58-slot 12 dB validation only after those gates; audit terminal
   status, all CSV/PNG and IQ lineage/hashes. Do not relabel the failed old run.
8. Then qualify Keysight VSA/VSG playback and the single-carrier 400 MHz / 7 GHz
   study, 1024-QAM UL / 4096-QAM DL and the 30 dB scenario. Eight-layer/config
   generality and later NTN/ISAC are not claimed complete by these repairs.

Earlier fixed, scoped components also include normalized PUCCH power,
DTX/report propagation, DL/UL received-control handoffs and gNB physical-TX
HARQ expectations. None establishes an all-channel, all-measurement PASS.
