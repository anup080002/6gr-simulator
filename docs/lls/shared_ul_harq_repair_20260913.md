# Two-port shared UL HARQ follow-up

This checkpoint extends the approved two-port SRS/PUSCH path. It is not the
final 58-slot run, a full main-scheduler qualification, or a conformance claim.

## Root causes repaired

1. The UL combined decoder borrowed base graph, TBS and CRC metadata from
   `tx`, despite the first-pass receiver having its own coding layout. It
   also discarded the code-block CRC error returned by desegmentation.
   `decodeCombinedULSCH` now takes the receiver coding layout and actual
   mother-code LLRs, checks their dimensions, and requires both CB and TB CRCs.
   No transmitter object or expected payload enters this decoder.
2. The scenario catalog limited initial DL/UL MCS to 27 for every table.
   Defined-rate row 28 is valid for the 64-QAM tables. The catalog now permits
   28, while strict table-aware validation rejects an initial MCS without a
   defined rate. Reserved retransmission rows still require retained HARQ
   state; they do not become configured initial rates.
3. Shared PUSCH reception stopped borrowing the UE transmitter's RV, but the
   frozen-grant-to-config projection did not install RV. The receiver then
   used the YAML initial RV0 for the UE's actual RV2 transmission. The basic
   frozen coding header has no rate-match position map, so the receiver
   regenerated a self-consistent but wrong RV0 recovery layout. This caused
   the second attempt's approximately 50% payload errors and poisoned the
   otherwise position-aware combining path. `PUSCH_Rx` now binds RV, retained
   TBS and rate from the gNB's frozen scheduling/HARQ contract. Contradictory
   explicit receiver values are rejected, not silently preferred.

The CRC boundary follows [TS 38.212, clause 6.2.1](https://www.etsi.org/deliver/etsi_TS/138200_138299/138212/18.02.00_60/ts_138212v180200p.pdf).
The MCS distinction follows [TS 38.214, tables 5.1.3.1-1/-2 and clause 6.1.4.1](https://www.etsi.org/deliver/etsi_ts/138200_138299/138214/18.08.00_60/ts_138214v180800p.pdf).

## Focused evidence and diagnostic attempts

- Receiver-owned decoder: exact payloads passed at A=1160, 3824, 3840 and
  10000 bits (CRC16/CRC24A, BG2/BG1, one/two code blocks). A deliberately
  corrupted CB CRC, re-encoded with valid LDPC parity and unchanged TB CRC,
  was rejected. Invalid layout/LLR dimensions were rejected.
- Existing position-aware soft-buffer, initial-MCS/UCI, and received UE HARQ
  endpoint regressions passed. The endpoint vector retains 1160 bits across
  MCS 10/RV0 -> modulation-only MCS 31/RV2 -> a new NDI epoch, with UCI.
- The first new shared fixture attempt queued two outstanding SRS captures.
  The owner rejected that setup. The fixture now schedules fresh SRS only
  after receiving the prior observation; the owner's causal guard is intact.
- At configured 12 dB, MCS 24 decoded successfully (reported post-equalization
  SINR 21.222 dB). The NACK-required fixture consequently failed instead of
  manufacturing feedback. This is not a PHY failure or full-run performance
  result. The stress YAML now requests MCS 28; the baseline YAML is unchanged.
- The MCS-28 attempt exposed the catalog limit above before waveform execution.
  Its decoder checks passed, but the enclosing process failed configuration.
- Scenario-configuration and HARQ-TB-context regressions passed.
- The first completed shared NACK/retransmission test (`_04`) exited zero
  under its original **wiring-only** assertions, but both TB CRCs failed:
  9 bit errors in RV0, 10053 in RV2, with unchanged 19968-bit TB and TPMI 3.
  Auditing those values exposed the missing receiver RV handoff above.
  This process is NOT packet-recovery acceptance evidence. The test now
  requires successful combined CRC and exact original payload, and saves
  real HARQ soft-state MAT captures for further diagnosis without rerunning.
- The corrected `_05` shared retry exited zero and satisfied the stronger
  recovery assertion: configured 12 dB, MCS 28, two ports / rank one, TPMI 3,
  original TBS 19968 bits throughout. Slot 10/RV0 failed with 9 payload bit
  errors. Slot 20/RV2 failed standalone decoding but **passed after combining,
  with zero payload bit errors**. Both actual timing estimates were 84 samples
  with zero residual timing error. The first attempt decoded the exact ACK
  bits `[1;0]`; the second did not repeat already-delivered UCI.

All process exits and diagnostic failures are recorded in
[the terminal receipt](evidence_20260913/shared_ul_harq_terminal_receipt.json).
The committed raw two-row CSV and two HARQ-state MAT captures come from `_05`;
the failed-recovery `_04` CSV is retained separately. CSV/image consistency,
per-symbol EVM and received-window carrier RSSI were checked by the component
test's independent numerical reconciliation and live-plot publisher checks.
These are component snapshots, not a terminal publication receipt for the
full baseline. The per-symbol EVM raster was also inspected visually.
Both [slot-10](evidence_20260913/slot10_live/manifest.json) and
[slot-20](evidence_20260913/slot20_live/manifest.json) snapshots are preserved
with eight PNGs each; every copied artifact matched its publisher SHA-256.
Raw log/capture hashes are in
[artifact_hashes.json](evidence_20260913/artifact_hashes.json). Original MAT,
CSV and plot captures remain at their local temporary paths; terminal logs
were moved into this repository's structured evidence folder without changing
their bytes. No local simulation output was deleted.

The shared fixture is an explicitly isolated 21-slot component: real
SS/PBCH timing, shared CDL SRS/PDCCH/PUSCH, rank one over two logical UL ports,
and a declared initial TAG. Its two first-attempt ACK bits originate in
separate actual DL waveform decodes. Once delivered, those bits are not
repeated on the UL retransmission. This does not qualify dynamic DAI, a
fresh UCI payload on every retransmission, or the full access/AMC scheduler.

## Remaining final-baseline gates

- Full main-scheduler shared retransmission integration and receiver state;
  the direct shared-owner coordinator fixture above is not that complete runner.
- Strict production DL received-allocation / UE receiver HARQ integration.
- Dynamic DAI and monitoring-occasion-aware Type-2 HARQ-ACK construction.
- `testDataChannelStreamStages`: disabled-power assertions still assume a
  finite requested dBm value. The proposed mode-aware repair was again
  rejected by the file-edit tool; the file remains unchanged. No ACL or
  alternate-write bypass was attempted.
- Then one final 58-slot configured-12-dB run and CSV/PNG/IQ/terminal audit.

The single-carrier 400 MHz/7 GHz, higher-QAM, 30 dB and instrument-playback
work remains downstream. No `testAll` or E2E campaign was started.

## Commands

```powershell
matlab -logfile ul_harq_decode.log -batch "setup6GRSimToolkit('Verbose',false); assert(testULReceiverOwnedHARQDecode);"
matlab -logfile ul_harq_shared.log -batch "setup6GRSimToolkit('Verbose',false); assert(testScenarioInitialMCS28); assert(testSharedPUSCHChannelArtifacts('TDD',false,false,false,true,true,true));"
matlab -logfile ul_harq_regression.log -batch "setup6GRSimToolkit('Verbose',false); runFocusedTests({'testHARQSoftBufferPositionAware','testPUSCHUCIInitialMCS','testReceivedULHARQState'});"
```
