# UE-owned DL HARQ endpoint checkpoint

## Implemented

`ReceivedDLHARQState` now owns the UE's connected C-RNTI process state,
initial coding identity, recovered soft bits, NDI transitions and delivery
decisions. It receives actual decoded control and captured samples, not
transmitter payloads, coding plans, precoders or injected noise variance.
The strict PDSCH receiver admits this typed state while continuing to reject
raw legacy soft-buffer overrides.

`ReceivedDLHARQCodingHistory` retains the original TBS, coding rate and
segmentation. Current received MCS still determines current modulation; the
nominal current-row rate is labeled separately from the retained coding rate.
Modulation-only retransmission MCS 31 therefore does not become an invented
new-TB rate. Context, UE, process, NDI, chronology and coding-domain mismatches
are rejected. A defined-rate retransmission changing TBS is rejected explicitly.

An already decoded process acknowledges the previous successful TB without
decoding or delivering it again. That decision produces no fabricated current
PHY CRC, timing estimate or trial row. It is **not** proof that HARQ feedback
was transmitted or received: `FeedbackTransmissionQualified` remains false.
These boundaries implement the scoped behavior in
[TS 38.321 clause 5.3.2.2](https://www.etsi.org/deliver/etsi_ts/138300_138399/138321/18.01.00_60/ts_138321v180100p.pdf)
and the MCS/TBS distinction in
[TS 38.214 clause 5.1.3](https://www.etsi.org/deliver/etsi_ts/138200_138299/138214/18.08.00_60/ts_138214v180800p.pdf).

## Focused evidence

The component generated independent coded PDCCH/PDSCH transmissions and
received them through the new UE endpoint. Four actual captures are preserved:

| Attempt | Received MCS / RV / NDI | Actual outcome |
| --- | --- | --- |
| 1 | 10 / 0 / 1 | Initial CRC failure; measured timing 42 samples |
| 2 | 31 / 2 / 1 | Combined CRC pass; exact original 1064 bits; measured timing 43 |
| 3 | 31 / 2 / 1 | ACK from previous decode; no new decoding or duplicate delivery |
| 4 | 10 / 0 / 0 | Fresh process; exact new payload; measured timing 43 |

The fixture deliberately uses -12 dB sample AWGN initially and 35 dB for
later captures. It is neither the configured-12-dB baseline nor statistical
link performance evidence. Expected payload is used only in test assertions,
not passed into reception. All allocations occupy legal DL slots; enabled
SSB reservation guards remain active.

The component and five coding/assignment/DL/UL regressions exited zero.
Replaying the four saved captures reproduced all decisions and decoded bits;
seven negative guards and three further focused regressions logged PASS.
The replay process no longer exists, but its terminal handle was unavailable
after context recovery: its exit code is recorded as unknown, not invented.
The complete log is preserved. No second waveform simulation was needed for
the replay. The later capture-timing regression did generate its own bounded
static/CDL receiver fixtures.

Three earlier failed attempts are retained honestly:

1. The fixture incorrectly demanded exact timing in the intentionally failing
   -12 dB capture. It now retains measured timing and requires exact timing
   only for the successfully acquired high-margin captures.
2. The original fixture placed a retransmission over a periodic SSB burst.
   It was moved to legal DL slots, without disabling the reservation guard.
3. The first handoff attempted a forbidden raw soft-buffer override. The
   implementation now uses typed UE-owned state; the prohibition remains tested.

[The receipt](evidence_20260913/dl_received_harq_terminal_receipt.json) records
process status, exact log/capture hashes and scope. Original temporary captures
remain local; the five copied evidence files were checked byte-for-byte by
SHA-256. The decision CSV is not a primary per-decode PHY result table.
No full 58-slot baseline, `testAll` or E2E campaign was run under the current
focused-test instruction; the generic full-suite requirement is not claimed met.

## Still mandatory before the final baseline

1. Wire the endpoint and per-UE state into the main shared scheduler using
   actual received DCI availability and capture timing. The first-pass legacy
   runner still has TX-derived inputs; this component does not qualify it.
2. Handle ACK-from-prior-decode as a protocol decision in that runner, not a
   fabricated current PHY trial. Qualify QCL timing transfer on this path.
3. Complete dynamic DAI, monitoring-occasion ordering and Type-2 HARQ-ACK
   construction/feedback delivery.
4. Repair the recorded disabled-power assertion in
   `testDataChannelStreamStages`; its prior file-edit refusal remains unresolved.
5. Then run one final 58-slot configured-12-dB baseline and audit terminal
   CSV/PNG/IQ, manifests and hashes. Do not reconstruct missing runtime rows.

The approved baseline already enables two-port SRS/PUSCH. The separate
[shared UL checkpoint](shared_ul_harq_repair_20260913.md) selected measured
TPMI 3 and recovered 19968 bits after combining at configured 12 dB. This
checkpoint does not change those settings or force DL/UL SINR equality.
Single-carrier 400 MHz/7 GHz, higher QAM, 30 dB, Keysight playback and the
later long impaired runs remain downstream, not silently dropped.

## Commands

```powershell
matlab -logfile dl_received_harq.log -batch "setup6GRSimToolkit('Verbose',false); assert(testReceivedDLHARQState);"
matlab -logfile dl_received_harq_replay.log -batch "setup6GRSimToolkit('Verbose',false); assert(testReceivedDLHARQReplay); runFocusedTests({'testPDSCHCompatibilityFacadeDelegation','testPDSCHAssignmentCaptureTiming','testHARQSoftBufferPositionAware'});"
```
