# DL receiver CRC / combined-decoder checkpoint

This is a focused coding and receive-path repair, not qualification of the
main shared scheduler or a new 58-slot baseline execution. The approved
two-port SRS/PUSCH configuration and its measured TPMI-3 shared recovery
evidence remain unchanged; see [the UL checkpoint](shared_ul_harq_repair_20260913.md).

## Root causes and repairs

- The single-codeword DL throughput HARQ path borrowed base graph, TBS and
  CRC type from the transmitter when decoding combined soft bits. It also
  substituted the TX coding layout when receiver layout evidence was absent.
  It now requires `rx.CodingLayout` and invokes `decodeCombinedDLSCH` with
  that layout and actual combined mother-code LLRs. Missing receiver layout
  is an error. The old TX-dependent decoder and its unused shape helper
  were removed.
- That combined decoder discarded code-block CRC errors. The replacement
  requires both code-block and transport-block CRC success and exact decoded
  TB length, with checked mother-code dimensions.
- The canonical `DLSCHDecoder` exported CB CRC failures separately but used
  only the TB CRC for its overall `CRCPass`. Its overall per-codeword and
  aggregate verdicts now include CB failures. Separate
  `TransportBlockCRCPass` / `TransportBlockCRCError` fields preserve the raw
  TB-only decision; a valid TB CRC is not relabeled as a failed TB CRC.

Coding references are [TS 38.212, clauses 7.2.1--7.2.3](https://www.etsi.org/deliver/etsi_ts/138200_138299/138212/18.08.00_60/ts_138212v180800p.pdf):
TB CRC attachment, base-graph selection and CB segmentation/CRC attachment.
The receiver acceptance gate is an implementation safeguard, not a claim
that 3GPP prescribes one universal receiver algorithm.

## Focused validation

`testDLReceiverOwnedHARQDecode` uses independent Toolbox coding as a numerical
oracle, not a waveform-performance or shared-clock result. It checks 16
combinations: A=1160/3824/3840/10000 bits and RV=0/2/3/1, spanning CRC16/CRC24A,
BG2/BG1, and one/two code blocks. It checks both the combined-decoder primitive
and the canonical rate-recovery/decoder entry point. Negative vectors corrupt
only a CB CRC, then re-encode valid LDPC parity while retaining the payload
and valid TB CRC. Such results must fail the overall decision. Layout/LLR
shape errors and transmitter objects at the combined-decoder boundary are
also rejected. An additional two-codeword case checks aggregate rejection
when only one codeword has this CB CRC fault.

The first vector invocation passed. Five existing focused regressions passed:
`testPDSCHNoNoiseRoundTrip`, `testPDSCHTwoCodewordCoding`,
`testPDSCHReceiverNoNoiseExact`, `testHARQSoftBufferPositionAware`, and
`testConnectedDataAllocation`. These include 12 receiver codewords across
ranks 1--8 with zero bit errors and actual decoded-control allocation tests
for both directions. Their scope remains component validation.

The expanded vectors, including the two-codeword CB-CRC negative, passed.
The accompanying throughput-entry-point test initially failed. Its returned
error identified a pre-transmission configuration conflict: the isolated
12-RB calibration fixture inherited enabled 20-RB SS/PBCH configuration,
triggering `InvalidSSBPointAOffset`. The fixture now explicitly disables
untransmitted SSB; the baseline and production SSB validator are unchanged.
The focused throughput-contract retry passed. Its constructed typed context
is a component fixture, not proof of real received DCI in the main scheduler.

The [terminal receipt](evidence_20260913/dl_receiver_crc_terminal_receipt.json)
preserves every process exit and SHA-256 for all five logs, including the
two failed diagnostic invocations. No `testAll`, E2E campaign or full
58-slot scenario was launched. Broad repository qualification is not claimed.

## Mandatory work not closed by this patch

1. `runDLPDSCHThroughput` still supplies TX-owned coding plans and allocation
   inputs to first-pass reception. Requiring its returned layout does not
   make that initial materialization independent. Production DL must build
   a typed receive assignment from accepted connected DCI and installed UE
   policy, with UE-owned HARQ history and no authored-grant receive authority.
2. The typed PDSCH facade rejects assignment-owned timing-search windows and
   bypasses the calibration adapter's tracking/physical-measurement bridge.
   The shared clock, QCL timing transfer and measurement evidence must be
   wired together before switching the production receiver to that entry point.
3. Main-scheduler UL/DL shared HARQ integration still needs qualification.
   The passed two-port UL direct shared-owner test is not the complete runner.
4. Dynamic DAI / monitoring-occasion-aware Type-2 HARQ-ACK construction,
   and the previously recorded disabled-power assertion repair remain open.
5. Only after those gates: one final configured-12-dB 58-slot run and complete
   CSV/PNG/IQ/hash/terminal audit. Single-carrier 400 MHz/7 GHz, higher QAM,
   30 dB, long impairment runs and instrument playback remain downstream.

## Commands

```powershell
matlab -logfile dl_receiver_vectors.log -batch "setup6GRSimToolkit('Verbose',false); assert(testDLReceiverOwnedHARQDecode);"
matlab -logfile dl_receiver_regression.log -batch "setup6GRSimToolkit('Verbose',false); runFocusedTests({'testPDSCHNoNoiseRoundTrip','testPDSCHTwoCodewordCoding','testPDSCHReceiverNoNoiseExact','testHARQSoftBufferPositionAware','testConnectedDataAllocation'});"
```
