# Shared retained-ACK feedback checkpoint

This is progress toward the final 12 dB baseline, **not** a completed baseline
or a full shared retransmission qualification. No full 58-slot run was started.

## Implementation

- The main shared DL callback recognizes an already-decoded process/NDI
  before invoking the PHY wrapper. It verifies the already-started TX ledger,
  queues a protocol-only ACK, records reception once and advances completion
  using the source slot's actual runtime `FrameLocal` coordinate. It does not
  append a PDSCH trial, another packet delivery, or a new SINR/EVM sample.
- `queueRetainedDLACKRuntime` retains the exact accepted control record and
  UE HARQ entity. K1, PRI, process, NDI, RNTI and source slot are checked
  against the received assignment; the received DCI supplies the feedback
  occasion. Configured PUCCH resources and the existing actual UCI execution
  path remain in use. Queuing does not call gNB `onFeedback`.
- `HARQProtocolDecisionEvidenceJSON` is a separate feedback timing domain.
  It binds control availability, protocol-decision availability and sample
  rate to current/prior assignment identities. Current PDSCH receive-time
  fields remain inapplicable, rather than relabeling an old timing estimate
  or a protocol event as a new decode. The UCI availability gate checks this
  domain without weakening the existing actual-data timing contract.
- Pending-feedback, PUCCH-trace and due-UCI collection retain the same
  evidence. Direct trace collection also maps its real
  `ScheduledAbsoluteSlot` to `DueSlot`; it must not lose the feedback clock.
- Review of the OLLA consumer exposed another loss: the PUCCH trace omitted
  NDI, RV and `IsRetransmission`. They now propagate from the source feedback
  row. In particular, a retained ACK must not reach link adaptation as
  first-transmission feedback merely because the trace dropped its flag.
- Nonempty protocol events publish separately as
  `harq/csv/received_dl_protocol_decisions.csv`. The semantic auditor checks
  identity, integer/bit/sample domains, causal clocks, prior decoded-TB or
  earlier protocol lineage, and absence of a duplicate current PHY decode.
  A prior NACK cannot support a retained ACK. No protocol ACK is counted as
  an already-executed PUCCH.

These changes implement the previously decoded-TB distinction in TS 38.321
V18.1.0 section 5.3.2.2. That section also requires separate feedback
eligibility rules, including time alignment. The availability gate is **not**
proof of all N1, TAG, DAI/codebook or multiplexing requirements.
[ETSI TS 38.321](https://www.etsi.org/deliver/etsi_ts/138300_138399/138321/18.01.00_60/ts_138321v180100p.pdf).

## Evidence and scope

- `retained_ack_feedback_timing_01.txt`: exit 0; 15 protocol timing guards,
  pending/trace projection, plus the actual SRS/PUCCH timing and power
  regression pass. Its ACK donor is actual isolated DL, not shared DL.
- `retained_ack_feedback_timing_02.txt`: final-source exit 0; the same checks
  plus direct PUCCH-trace due-UCI collection pass after repairing its due-slot
  projection. Actual SRS/PUCCH timing/power also passes on this source.
- `retained_ack_feedback_queue_01.txt`: exit 1. The direct component setup
  omitted `run.rootRunFolder`, which the production runner normally binds.
  The required continuous-IQ guard was retained and the test setup repaired.
- `retained_ack_feedback_queue_02.txt`: exit 0. The advanced shared clock
  and actual archived UE decode lineage produce one pending reservation,
  no new decoder/delivery rows and no gNB feedback update; five negative
  guards pass. CCE/binding inputs are declared unit-fixture inputs, not a
  claim that a fresh shared PDCCH or PDSCH executed in this test.
- `retained_ack_semantic_tests_01.xml`: 122 Python tests pass, including
  retained-ACK semantics, existing CSV semantics and exhaustive inventory.
- `retained_ack_scheduler_grants_01.txt`: the dedicated scheduler grant
  consistency test exited 0. Its quiet log is not a full-run receipt.
- `retained_ack_feedback_final_03.txt`: final-source exit 0 after adding
  NDI/RV/retransmission propagation. Queue guards (including preserved HARQ
  identity), all 15 timing guards, actual SRS/PUCCH timing/power and scheduler
  grant consistency pass in this single focused process. The `_03` queue
  and timing CSVs are retained alongside the earlier evidence.

The queue fixture retains four raw `cf64le` files below its
`physical_clock_capture/waveform/raw` directory. Each has 407,040 samples,
6,512,640 bytes and SHA-256
`d4d85e307fc915e9024ff3c33127707ca6172f62954a9c967085bad5efdc33e8`.
Every byte was checked by comparison with the hash of an equal-length zero
buffer. These are **empty-clock test captures**, not channel-bearing waveforms,
not a terminal IQ-manifest qualification and not Keysight playback evidence.

## Remaining mandatory work

1. Execute a complete shared retransmission / retained ACK / actual UCI
   reception test, including gNB HARQ outcome, processing deadlines and TAG
   eligibility. The queue and ordinary PUCCH component tests are not a
   substitute for this combined test.
2. Qualify the main callback's completion counters and terminal reductions
   with protocol-only dispositions as well as actual decoder trials. Audit
   current received-control and transmitted-TB lineage across the full run.
3. Repair failed-DCI handling using a gNB observation/DTX path, not an
   invented UE assignment or feedback bit.
4. Resolve the unchanged CSI-RS allocator write restriction, then repair
   its non-occasion reservation and regenerate only the affected captures.
5. Complete special-slot K1/TDRA, independent TA/synchronization,
   measurement-domain, applied-beam and artifact/publication gates before
   the final 12 dB run. The 400 MHz / high-QAM / 30 dB stages remain afterward.
