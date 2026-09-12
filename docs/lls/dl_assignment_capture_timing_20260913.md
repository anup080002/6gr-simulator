# Assignment-owned DL capture timing

This checkpoint repairs a prerequisite for production DL received-assignment
integration. It does not qualify the main scheduler, replace received DCI
materialization, or start a new 58-slot baseline.

## Runtime repair

Previously the typed PDSCH receive facade rejected every
`TimingSearchWindowSamples` request and passed its input directly to OFDM
demodulation. A real shared capture need not begin at the arriving slot.

The typed path now derives DM-RS from its immutable assignment and reference
configuration, verifies the carrier's absolute slot, and uses received-reference
correlation inside the declared search window. Frequency acquisition first
gets symbol-aligned received samples; correction is applied to the actual
capture, followed by measured timing and complete-slot extraction. It reuses
the existing receiver tracking implementation, not a TX timing or delay value.
Fast/skip/already-aligned bypasses remain forbidden for this unaligned input.

Actual receive-timing, applied correction, synchronization and CFO evidence
are returned in `rx`/`info`. When a separate antenna-plane waveform is supplied,
the same measured frequency/timing correction is applied to that capture and
its immutable OFDM options are used for the physical measurement grid. Invalid
or incomplete supplied measurements fail; no replacement grid or padding is
manufactured. Aligned callers without a search-window request retain their
existing execution path.

The current acquisition helper uses the native carrier FFT/sample clock and
symbol-phase convention. A different immutable FFT/sample-rate/phase convention
is rejected explicitly instead of producing incorrect timing in another sample
domain. Supporting such captures requires a matching acquisition implementation;
this checkpoint does not qualify custom-rate instrument playback or 400 MHz.

Practical correlation and configurable sample-rate/FFT semantics are documented
in [nrTimingEstimate](https://www.mathworks.com/help/5g/ref/nrtimingestimate.html).
In particular, OFDM symbol-length counts are at the IFFT clock and are not
automatically waveform-sample counts after arbitrary resampling; see
[nrOFDMInfo](https://www.mathworks.com/help/5g/ref/nrofdminfo.html).

## Focused evidence and failures retained

`testPDSCHAssignmentCaptureTiming` is an explicit typed-allocation component
fixture. Its calibration assignment is NOT evidence of actual received DCI.
The receiver builds its coding plan independently from receiver-side dimensions;
no TX coding plan or precoding matrix enters reception. Deliberately conflicting
initial PRB/NSCID config does not replace the immutable receiver allocation.

- Static 2x2 channel: injected delays 0 and 43 samples were measured exactly;
  injected frequency offsets -700 and +700 Hz were estimated exactly to displayed
  precision. All 384 payload bits decoded without errors in both captures.
- Physical-plane grids agreed numerically with the independently scaled decode
  grids after identical measured alignment. The receiver used finite
  K-by-symbol-by-RX-by-layer channel tensors, not a scalar full-grid substitute.
- Truncated capture, timing bypass, invalid physical samples and wrong absolute
  slot were rejected. Custom FFT and symbol-phase rejection is also tested.
- Actual `nrCDLChannel` CDL-C, 100 ns delay spread and 30 Hz maximum Doppler:
  bounded acquisition measured 50 samples and decoded all 384 bits without
  errors. The CP frequency estimate was 673.749 Hz for an injected 700 Hz
  oscillator shift. A time-varying channel contributes to this received
  common-frequency observation; it is not forced to the oscillator setting.
  This is a component capture without an injected AWGN operating point, not
  a configured-12-dB performance result.
- Existing compatibility-facade, CDL receiver and FRC measured-CFO regressions
  passed. The FRC check is one focused transport block, not a full campaign.
- The first new fixture failed because it omitted the required coding plan.
  It was repaired by independently resolving that receiver plan, not by relaxing
  the missing-plan guard. The misleading diagnostic saying plans must originate
  at the transmitter was corrected; the object/dimension checks remain intact.
- The second attempt decoded successfully but failed a test's wrong estimator
  label expectation. The replacement checks the actual tensor dimensions,
  finite samples and absence of scalar channel output. That attempt remains
  a failed process, not an overall passing test result.

The final retry including both custom-clock guards passed. Three runtime MAT
captures and two measured CSV tables are preserved in
[the capture directory](evidence_20260913/dl_assignment_capture/), alongside
all five terminal logs. The [terminal receipt](evidence_20260913/dl_assignment_capture_terminal_receipt.json)
records each exit and artifact SHA-256, including both earlier failed fixtures.
Original temporary captures remain local and unchanged.

## Remaining mandatory integration

1. Materialize strict connected DL receive assignments from accepted DCI and
   installed UE configuration, with independently retained UE HARQ TB state.
2. Wire those objects and the now-supported native-clock capture window through
   the main scheduler; preserve physical measurement, QCL/TCI and CSV evidence.
3. Qualify shared UL/DL scheduler HARQ, dynamic DAI/monitoring-occasion-aware
   Type-2 HARQ-ACK construction, and the recorded disabled-power assertion repair.
4. Only then run the final configured-12-dB 58-slot baseline and audit all
   CSV/PNG/IQ/hash/terminal outputs. Higher bandwidth/QAM, 30 dB, long impairment
   qualification and Keysight playback remain downstream.

No `testAll`, E2E campaign, or full 58-slot run was launched for this checkpoint.

```powershell
matlab -logfile dl_capture_timing.log -batch "setup6GRSimToolkit('Verbose',false); assert(testPDSCHAssignmentCaptureTiming);"
matlab -logfile dl_capture_regression.log -batch "setup6GRSimToolkit('Verbose',false); runFocusedTests({'testPDSCHCompatibilityFacadeDelegation','testPDSCHReceiverCDL','testFRCPDSCHCFOTracking'});"
```
