# Received DCI to UE HARQ event: tested component, integration pending

This follows the [12 dB closure plan](12db_measurement_closure_plan_20260913.md).
It does not qualify the 58-slot baseline, shared PUCCH/PUSCH feedback, the
detector, full measurement closure or the later impairment campaign.

## Implemented event boundary

`sixgr.link.receivedDLHARQACKEvent(installed, assignment, decision, after)`
requires the CRC-accepted connected assignment capsule, complete UE decision,
and the private-set UE HARQ entity after that exact assignment was consumed.
It rejects mismatched context, assignment digest, process/NDI, control/data
clock, attempt count and ACK state. It also rejects contradictory decode,
retained-ACK and TB-delivery flags and any claim that feedback has already
been transmitted. A scheduler ACK flag or source label alone is insufficient.

The event retains raw received DAI and its semantic value, epoch, UE/RNTI,
configured serving-cell index, assignment/payload/context digests, received
K1/PRI, absolute control/data/feedback slots and an explicitly one-based
planner target slot. Monitoring order uses the absolute OFDM-symbol clock
of the supported scalar-start connected monitoring configuration, whose
digest is also retained. This is not a gNB scheduling ordinal or modulo DAI.

Scope is the installed ordinary single-cell 1_1, one-TB, two-bit-counter-DAI
profile, with no CBG or optional DCI extensions. Unsupported variants fail
rather than being silently folded into the scalar procedure. Priority zero
is the default for this profile without a priority indication, not a
scenario tuning constant. See [TS 38.213 V18.8.0, clause 9 and 9.1.3](https://www.etsi.org/deliver/etsi_ts/138200_138299/138213/18.08.00_60/ts_138213v180800p.pdf).

No current CRC, SINR, EVM or transmitted-feedback measurement is manufactured
for a repeated ACK. A missing counter-indicated codebook position is a
protocol NACK with no event/PDSCH identity, not an observed receiver DTX.

## Actual execution and retained failures

1. `sixgr_received_harq_event_20260913_01.log`: exit 1. The new adapter initially
   read the legacy `searchSpace.startSymbol` alias. The connected receiver
   actually uses `operatorControl.connected_monitoring.start_symbol` through
   `ConnectedPDCCHConfiguration`. The adapter now validates and reads that
   explicit policy; no default-zero rescue was added.
2. `_02.log`: exit 1 at archived retransmission recovery. The first actual
   NACK and its event checks passed; the expected retransmission ACK did not.
3. `_03.log`: exit 1, with same-IQ original-assignment versus changed-DAI
   comparison saved before failure. Both current replays fail CRC and have
   exactly equal layer symbols, descrambled LLRs, decoded TB and timing.
   Counter DAI does not cause this failure.
4. `sixgr_received_harq_calendar_capture_20260913_01.log`: exit 0. The unchanged
   `testReceivedDLHARQState` generated a fresh actual coded capture sequence
   with the current allocator, with actual NACK/recovery/retained-ACK/new-NDI
   outcomes. Every original assertion passed.
5. `_04.log`: exit 0. The event test decoded new PDCCH waveforms carrying each
   raw DAI value and replayed the fresh PDSCH captures. All 48 negative event
   guards passed. `testType2HARQACKLayout` also passed its literal gaps/wraps,
   256 DAI sequences, serialization and 24 vector regressions;
   `testType2HARQRuntimePlan` passed its existing typed resource-planning gate.

All named completed logs are under `evidence_20260913/`.

| Sequence | Actual raw DAI | Actual UE outcome | Current PHY decode? | Codebook tokens for this single received event |
| --- | ---: | --- | --- | --- |
| 1 | 0 | NACK | Yes, failed CRC | `0` |
| 2 | 1 | ACK, recovered TB | Yes, passed CRC | `01` |
| 3 | 2 | ACK, retained decoded TB | No; no duplicate delivery | `001` |
| 4 | 3 | ACK, new NDI | Yes, passed CRC | `0001` |

Each row is a separate feedback occasion. The leading NACK positions test
the procedure response to an actually received counter; preceding missed
PDCCH waveforms were not executed in this component. Multi-assignment shared
feedback, actual missed DCI, wraps on the physical timeline and RX disposition
remain integration requirements, not claims of this table.

## Why the old capture could not be reused

The original `received_dl_harq/` captures predate the CSI-RS nonoccasion calendar
repair. Their old data maps reserve REs on inactive CSI-RS occasions. The
current allocator correctly exposes those REs to data. Independent reads of
the old and new MAT records find:

| Attempt allocation | Archived data symbols / LLRs | Current symbols / LLRs | Retained TB size |
| --- | --- | --- | --- |
| Six PRBs, Qm=4 | 765 / 3060 | 777 / 3108 | 1064 bits |
| Eight PRBs, Qm=6 | 1020 / 6120 | 1036 / 6216 | 1064 bits |

Thus an old waveform is not a valid golden capture for the newly corrected
rate-matching/resource map. Neither toggling DAI, changing noise, reintroducing
phantom reservations nor padding/cropping old samples is an acceptable repair.

The fresh fixture is preserved separately in
`evidence_20260913/received_dl_harq_calendar_02/`; old captures are unchanged.
The failed same-IQ comparison is in
`evidence_20260913/received_harq_old_calendar_replay_failure_01/`.
The new event/control/receiver/codebook records are in
`evidence_20260913/received_harq_event_04/`.
`received_harq_event_component_receipt.json` records source hashes, 13 verified
copy hashes and scope. These are isolated endpoint captures at -12/35 dB,
not shared-CDL or 12 dB baseline measurements. The third ACK uses retained
state rather than another PDSCH decode.

## Regression and main-runtime integration still required

`testAll.m` currently omits the received-DL replay/reporting tests. Therefore
its running executions cannot establish that these captures still replay.
`pending_received_harq_calendar_tests.patch` redirects five actual-replay tests
to the new versioned fixture without changing their assertions, and registers
11 relevant receiver/DAI/calendar gates. `git apply --check` passes. **This
patch is unapplied and its five migrated tests are not yet qualified.**
It must be applied and validated once no live suite uses those source files.
The new event test is callable now but also awaits registry integration.

Main handoff points inspected:

- `runDLPDSCHThroughput` returns `ReceivedHARQDecision` and `ReceivedHARQState`.
  The new event can be created there using the received assignment.
- `runWaveformLinkBundle` commits that UE state at actual data completion.
  The event must cross this same clock boundary and enter UE-owned feedback
  state, not be reconstructed later from a scheduler grant.
- `queueRetainedDLACKRuntime` must retain the decision it currently discards
  and create the same protocol event without generating a PDSCH trial.
- `observePUCCHFeedback` still appends expected bits by feedback-row index.
  Replace that path with the received-event codebook and retain gap identities
  through both PUCCH and PUSCH UCI.
- `applyObservedPUCCHFeedback` also indexes received bits by row. gNB mapping
  must instead be derived from its independently transmitted schedule and
  actual received feedback. The gNB must not borrow the UE's event mapping or
  assumed payload length to claim successful missed-DCI reception.
- `SharedDLHARQExpectations` retains transmitted DCI and timing independently;
  it still needs the receive-only occasion consumer. Detector and Phase-05
  evidence gates remain intact and open.

No existing runtime dependency or running test registry was modified by this
component work. The 12-test development config/LLS/export/grant/E2E guard batch
completed with `PROJECTION_GUARD_EXIT=0`, including E2E_TruthPacketSemanticCampaign
in 976.27 s and E2E_FastVsTruth in 724.26 s. Its retained log is
`evidence_20260913/sixgr_projection_revision_guards_20260913.log`.
The following development full-suite process is live; main/receiver full
suites remain on their earlier revisions. These results do not qualify the
pending patches or an integrated end-to-end feedback path.

The NR-validation and result-integrity skills guided preserving the failed
capture, using current actual waveforms, binding private UE state and keeping
component versus full-run qualification explicit.
