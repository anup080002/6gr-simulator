# Practical DL receiver precoder boundary

The approved two-port SRS/PUSCH, rank-one measured TPMI configuration remains
enabled in `lls_causal_access_to_data_wiring_tdd_short_continuous_iq.yaml`.
Its existing shared-owner recovery evidence is recorded in
[the UL checkpoint](shared_ul_harq_repair_20260913.md): actual TPMI 3, RV0
failure followed by RV2 combined recovery of the original 19968 bits.
No full 58-slot baseline was restarted for this checkpoint.

## Defect and repair

`PDSCHReceiver.localRXResolveIntegrationBinding` always supplied the optional
third argument to `PDSCHIntegrationValidator.bind`, even when the receiver
had no transmitter precoder. The validator interprets presence of argument
three as a request to authenticate an applied transmitter matrix. Consequently
the strict connected receiver rejected a valid receiver-only BWP/CC/epoch/TCI
context before reaching its practical logical-port DM-RS estimator.

The receiver now uses the two-argument binding contract when no matrix is
provided. Active cell, carrier, BWP, epoch, PRB mapping, timing and selected
TCI checks still execute. Transmitter-matrix binding remains explicitly
`NOT_EVALUATED`, with an empty digest; it is not exported as an applied or
validated matrix. Matrix-assisted receiver calls retain the full third-argument
guard. The validator and transmitter were not modified.

Practical DM-RS estimation measures the effective layer-to-receive-antenna
channel including precoding; it need not borrow the transmitter matrix to
equalize data. This matches the practical estimation path in
[MathWorks NR PDSCH Throughput](https://www.mathworks.com/help/5g/ug/nr-pdsch-throughput.html).
This software-boundary repair is not a conformance claim.

## Focused validation

The MATLAB process exited zero. `testPDSCHReceiverWithoutTXPrecoder` decoded
384 bits with zero errors through a non-diagonal static two-by-two channel,
with an independently resolved receiver coding plan and without a transmitter
matrix or true-channel oracle at RX. It checked the finite 72-by-14-by-2-by-2
effective estimate and truthful unevaluated matrix-binding status.

Seven negative checks passed: stale epoch, wrong BWP, inactive TCI, missing
integration context, supplied matrix without its binding, stale supplied
matrix binding, and an explicitly empty third validator argument.

Five regressions passed: compatibility facade delegation, TCI-state binding,
active-BWP binding, transmit/receive assignment-authority separation, and
the existing CDL receiver test. The new boundary test uses an explicitly
constructed assignment fixture, not decoded PDCCH evidence. Its Type-A
association does not demonstrate runtime QCL timing transfer or Type-D beams.

Command:

```powershell
matlab -logfile docs/lls/evidence_20260913/dl_rx_without_tx_precoder_20260913.txt -batch "setup6GRSimToolkit('Verbose',false); assert(testPDSCHReceiverWithoutTXPrecoder); runFocusedTests({'testPDSCHCompatibilityFacadeDelegation','testPDSCHTCIStateBinding','testPDSCHActiveBWPBinding','testPDSCHTransmitReceiveAuthoritySeparation','testPDSCHReceiverCDL'});"
```

The [terminal receipt](evidence_20260913/dl_rx_without_tx_precoder_terminal_receipt.json)
records the observed exit and exact log hash. No `testAll` or E2E campaign
was run, following the task's focused-test-only instruction. This is narrower
than the repository's generic all-suite validation requirement.

## Remaining mandatory gates

- First-pass production DL assignment/coding materialization from actual
  received DCI and UE-owned HARQ state, without transmitter coding plans.
- Main-scheduler shared DL/UL retransmission, clock and QCL integration.
- Dynamic DAI and monitoring-occasion-aware Type-2 HARQ-ACK construction.
- Recorded disabled-power assertion repair in `testDataChannelStreamStages`.
- Then one final 58-slot 12 dB baseline and terminal CSV/PNG/IQ/hash audit.

No scenario policy or PHY parameter changed in this boundary repair, so no
new YAML setting was introduced. No local outputs were deleted. Single-carrier
400 MHz/7 GHz, higher-QAM, 30 dB and instrument-playback work remains downstream.
