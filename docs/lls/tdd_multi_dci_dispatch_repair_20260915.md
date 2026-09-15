# TDD 5 MHz / 12 dB: multi-DCI dispatch repair and next blocker

Status: focused repair verified; integrated 12 dB acceptance NOT achieved.
FDD and 400 MHz implementation remain deferred.

## Retained integrated execution

Run `tdd_5mhz_12db_2c45b257_20260915`, source 2c45b257, passed access,
shared SRS reception, the previous slot-32 QCL boundary and three connected
DL transport blocks (slots 31–33). Each block carried 1,064 bits and passed
CRC. It ended at coordinator slot 35 with zero connected UL trial rows.

Original failure: `sixgr:truth:UnresolvedCombinedPUCCHReceiveHypothesis`,
from `buildScheduledHARQTransportReception` line 5, called by the empty-
producer branch of `prepareSharedPUCCHFeedbackRuntime` line 1256.
The failure report is under the run's `meta/failure_debug_report.txt`:
SHA256 `d3da1888fc7c9ba39c98b718608b95000cd78335fa93a6282751b74e48222b85`.
Raw CSV, IQ and failure history are retained under `logs/scenario_runs/lls`.
The process exited after recovery also failed with `MATLAB:invalidConversion`
(conversion to double from cell). This is not a finalized successful run.
Queue 10 was stopped while waiting, before guards or testAll started.

## Separate slot-34 control defect: repaired

Both slot-34 PDCCH rows had two context-valid blind hypotheses, but the
scalar receiver rejected the combined set as ambiguous. Both DL and UL
grants were then withheld. The candidate vectors retained the two valid
decodes. This is not evidence that both transmitted commands failed CRC.

`PDCCH_Rx` correctly preserves its complete candidate set and must retain
its scalar ambiguity rejection. The missing integration was in
`runWaveformLinkBundle.localCompletePDCCHTrial`, which consumed only that
scalar result even when a shared slot carried different directional DCIs.

`+sixgr/+link/selectConnectedPDCCHDirection.m` now dispatches context- and
CRC-accepted observations using their decoded direction. Within a direction,
the existing payload-equivalence reducer still rejects conflicting commands.
Neither expected TX bits, transmitted format/size nor candidate location
selects the result. The complete candidate set remains available for audit;
CSV columns distinguish directional reduction from the composite count/class.
Standalone scalar monitoring remains unchanged when there is no grant.

## Executed verification

- `logs/testall_20260915T145144011Z_b2009311`: the new actual composite-
  waveform test passed in 25.99 s. Both DL/UL assignments materialized;
  poisoned expected bits did not affect dispatch; absence/conflict rejected.
- `logs/testall_20260915T145314730Z_cdf045b9`: 4/6 passed. Two stale fixtures
  failed: the causal gate lacked explicit control-slot authority and the
  structural test searched for the reducer's old single-output signature.
- `logs/testall_20260915T145505342Z_93f56110`: all 6 passed after fixture
  repair. Tests: ConnectedPDCCHBlindMonitoring, ConnectedDCIMaterialization,
  PDCCHEquivalentBlindHypothesisReduction, PDCCHReceivedCandidateContext,
  PDCCHCausalDCIGrantGate, and PDCCHRuntimeReceptionIntegrity (all `test`-
  prefixed). The missing-control-clock rejection remains an explicit negative
  test. No existing correctness assertion or decoder threshold was relaxed.

These are R2026a Update 4 diagnostic tests on frozen modified source based
on 190db704, not final-source full-suite or integrated acceptance evidence.

## Next repair sequence — not completed by this patch

1. `buildScheduledHARQTransportReception` and
   `CoupledTruthRuntime.prepareSharedPUCCHFeedbackRuntime`: replace blanket
   CSI-enabled rejection with installed periodic-calendar and resource-
   overlap authority. Trace the actual target feedback slot, not only the
   coordinator slot. The retained calendar has nominal CSI slots 4,9,...,54.
   Do not assume a pending UE report proves or disproves a gNB obligation.
2. Bind independent combined HARQ/CSI/SR receive schemas and transport
   ownership for actual overlaps; reuse `buildConfiguredPUCCHReceiveContext`,
   `buildPeriodicCSIReportObligations`, and scheduled PUSCH CSI obligations.
   Test CSI-enabled non-report slots, real report overlaps, missed/all-missed
   DCI, absent/late producers and PUCCH/PUSCH ownership. Do not disable CSI
   or merely delete the guard to advance the baseline.
3. Diagnose the retained failed-recovery cell conversion from persisted
   artifacts, then verify CSV/PNG publication and fixed-point consistency.
4. Run required testAll and strict/config/LLS/scheduler/export/E2E guards on
   the repaired source, and rerun the unchanged 5 MHz TDD / configured 12 dB
   scenario. The previous 46 full-suite failures and original detector
   qualification failure are not closed by these focused passes.

The earlier SRS availability repair is committed as 190db704; its three
focused tests passed. Its actual received scoring CSV and MAT evidence were
also copied into that test log folder under `shared_receive_evidence` without
removing the original temporary evidence. The original ZIP predates this
additional copy; share the folder to include the received MAT files.
