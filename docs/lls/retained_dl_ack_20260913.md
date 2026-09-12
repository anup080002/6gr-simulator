# UE retained-ACK disposition checkpoint

This checkpoint does **not** qualify the main shared scheduler or the final
58-slot 12 dB run. No full baseline was restarted.

## Root cause and repair boundary

The shared coordinator assumes every DL assignment yields a current PDSCH
decode row. Its connected receiver wrapper stops at
`sixgr:truth:RepeatedDLAckDispositionRequired` when the UE already decoded
the same HARQ process/NDI. A repeated ACK is not a new CRC success, delivered
TB, SINR sample or EVM sample.

`ReceivedDLHARQState` now exposes a read-only `requiresDecode` query and a
protocol-only `acknowledgeRetained` transition. Both validate the actual
received-control capsule and strict per-process control/data causality.
The transition verifies retained coding identity/TBS, advances only that
process's received-assignment history, and preserves its prior soft state.
It requires no current waveform or receiver-port count. The existing
`receive` entry point calls this transition for already-decoded TBs and
returns no PHY result. New/undecoded TBs still require actual IQ and execute
the original decoder/combining path.

The optional fourth output is `received_dl_retained_ack/v1`, a protocol
record with current and prior acknowledged assignment identities. The prior
acknowledged assignment is deliberately not called a new successful decode:
after multiple repeated ACKs it can itself refer to a protocol-only event.
The record contains no current CRC, SINR, EVM, timing estimate or decoded
payload. `FeedbackTransmissionQualified=false` remains explicit.

The relevant rule is TS 38.321 V18.1.0, section 5.3.2.2: retransmission
combining/decoding is required for an as-yet undecoded TB; a successfully
decoded connected TB is not delivered twice. Feedback also has separate
eligibility rules, including time-alignment state. This endpoint does not
claim those conditions or a transmitted/received PUCCH merely from ACK=1.
[ETSI specification](https://www.etsi.org/deliver/etsi_ts/138300_138399/138321/18.01.00_60/ts_138321v180100p.pdf).

## Focused verification

`testReceivedDLRetainedACK` consumes the preserved actual coded HARQ captures.
It checks the new-TB/NACK, combined-ACK, repeated-ACK and NDI-toggle routing,
empty-IQ repeated ACK, no duplicate delivery, unchanged soft state, untouched
other processes, capsule tampering, disabled HARQ and noncausal replay guards.
The generated CSV is a protocol-decision table, not a PDSCH measurement table.

Both focused MATLAB processes exited **0**:

- `evidence_20260913/received_dl_retained_ack_01.txt`: new protocol test,
  four actual HARQ replays and canonical combining evidence for attempts
  1, 2 and 4 pass (5,600 current/combined mother-code values; prior state
  participates only in attempt 2).
- `evidence_20260913/received_dl_retained_ack_02.txt`: final-source protocol
  test (11 negative checks) and actual connected DL donor pass. The donor
  decodes ACK at slot 3/process 0 and NACK at slot 6/process 1; it is an
  isolated component, not shared-channel or final-baseline qualification.
- The protocol CSV records one 1,064-bit retained TB, current control/data
  slot 52 (zero-based), previous acknowledged slot 42, ACK=1, decode=0,
  delivery=0 and feedback-transmission-qualified=0. These are protocol
  coordinates from archived captures, not new 12 dB run measurements.

No old captures or assertions were replaced to obtain a pass. No `testAll`,
E2E campaign or full baseline was run. Focused reproduction:

```matlab
setup6GRSimToolkit('Verbose',false);
testReceivedDLRetainedACK; % A new temporary output folder by default.
testReceivedDLHARQReplay;
testReceivedDLCombiningEvidence;
testReceivedDLFeedbackAuthority;
```

## Required next integration, still open

1. Carry protocol-only decisions through the shared coordinator without
   manufacturing `TrialTable` rows or invoking duplicate packet delivery.
2. Bind a repeated ACK to its current **received** K1/PRI/CCE and retained
   decode lineage. Represent control/protocol availability separately from
   current data decoding. `assertHARQFeedbackAvailable` currently requires
   actual current-data receive timing; do not disguise protocol timing as
   a new DMRS estimate to satisfy it.
3. Exercise actual shared PUCCH/PUSCH UCI encoding and reception, TAG/TA
   eligibility and processing deadlines for a repeated ACK. Only the actual
   received feedback may update the gNB HARQ process.
4. Repair failed-DCI disposition separately. No decoded assignment means
   the UE cannot learn K1/PRI from the gNB's planned grant. A gNB expected
   feedback observation/DTX path must be distinct from UE feedback creation.
   The current shared callback stops at `SharedDataDTXDispositionRequired`;
   simply returning would leave already-started gNB HARQ state unresolved.
5. Resume the other mandatory gates in the issue ledger before one final
   12 dB run. The non-occasion CSI-RS allocator write restriction is unchanged.
