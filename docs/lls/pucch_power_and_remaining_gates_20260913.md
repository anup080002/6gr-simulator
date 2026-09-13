# PUCCH power-domain repair and remaining 12 dB gates

Follow-up: [receiver disposition and special-slot TDRA repair](pucch_disposition_and_tdra_20260913.md)
records subsequent fixes and terminal focused-test results. The original
observations below are retained as checkpoint history, not current claims
that every listed implementation defect remains untouched.

This checkpoint is not a qualified full baseline. Do not launch another
58-slot run while the mandatory gates below remain open. Retain failed
captures; do not reconstruct missing runtime measurements after execution.

## Edit failure investigation

`PUCCHReceiver.m` and `allocREsPDSCH.m` remain unchanged. Both are normally
tracked (`git ls-files -v`: H), with no special Git attributes or index lock.
They are not read-only; visible ACLs grant modification. A Windows write-handle
open/close succeeded without writing bytes, with identical before/after hashes.
Repository-relative and absolute `apply_patch` attempts, including the installed
Codex patch engine, still report `Failed to write file`. Ordinary Git/GitHub
locking is not supported by this evidence. The patch-engine failure is unresolved;
no alternate writer, ACL change, deletion or source-file replacement was used.

Repository-local `core.longpaths=true` is now set. Without it two deep
historical CSV paths are misreported as inaccessible; they must not be deleted.
This repairs Git's long-path reporting, not the separate source-editor failure.

## Newly isolated physical defect

The typed PUCCH transmitter scales its actual IFFT samples to its absolute
power-control target and records `Power.WaveformScale`. The configured-Es/N0
branch of `applyPowerContext` assumes original normalized IFFT samples and
preserves its input. Passing already physically scaled PUCCH into that branch
left the signal near noise-only levels despite a nominal 12 dB reference.

In `pucch_baseline_signal_02`, the actual received PUCCH metric was
0.316864728345981 at threshold 0.42. Its typed target was -80 dBm, with two
HARQ bits expected and a DTX decision. This is not solved by weakening the
detector threshold or scaling the received waveform/noise to obtain a pass.

The shared/standalone TX preparation boundary now removes only the recorded
absolute TX scale when existing YAML enables `FIXED_SNR_SWEEP` and configured
SNR authority. Relative RE power and the original IFFT waveform are retained.
Physical-power modes retain their existing scaling. Missing scale evidence
fails explicitly. Normalized energy, amplitude units and applicability are
exported into the actual runtime PUCCH table; device dBm is not claimed for
normalized samples. This is a numerical reference-domain repair, not a new
3GPP-prescribed power-control rule or detector threshold.

`testPUCCHNormalizedTransmitReference` has passed the independent IFFT
comparison, physical-power closure and missing-scale negative guard. The
shared signal-present test uses the actual baseline UL configuration, with a
separately declared isolated DL feedback source; it is not full access or TA
qualification.

### Signal-present terminal result

`pucch_baseline_signal_tests_03.txt` reached exit **0**:
`PUCCH_NORMALIZED_REFERENCE_PASS`, `PUCCH_POWER_EXPORT_PASS` and
`SHARED_PUCCH_FEEDBACK_CLOCK_PASS`. Both expected HARQ decisions were received
(ACK, NACK), actual SRS preceded PUCCH, and retained receive timing and export
assertions passed. The normalized active-symbol mean-square is
0.0000457763671875, reference occupied-RE energy is 1, and removed absolute
amplitude scale is 0.0147801668912544. No device-power claim is made.

**Margin remains marginal:** the received metric is 0.420294752122787 versus
0.42. This one occasion only establishes successful execution and payload
recovery for this capture. It does not establish acceptable missed-ACK rates,
robust detection, or repair the prior noise-only false-ACK failure. No threshold,
noise realization or seed was changed to obtain the pass.

Reproduce the focused test with a new output directory:

```powershell
matlab -batch "setup6GRSimToolkit('Verbose',false); testPUCCHNormalizedTransmitReference; testPUCCHBaselineSignalClock('docs/lls/evidence_20260913/pucch_baseline_signal_NEW')" -logfile docs/lls/evidence_20260913/pucch_baseline_signal_tests_NEW.txt
```

## Access delay and special slots

Previous run coordinates, one-based: PBCH available 6, PRACH 15, RAR 17,
Msg3 20, Msg4 23, RRC setup complete 25, SRS 30, first PDSCH 31. At 15 kHz
SCS these are 1 ms radio slots, not MATLAB processing durations. Configured
occasions and the measured-SRS prerequisite explain this timeline. There is
no universal requirement to wait 30 slots in NR or in all simulators.

The old special-slot PDSCH start=2/length=12 cannot fit 10 DL symbols.
The current baseline YAML includes start=2/length=8, but actual scheduler
selection and legal K1/PUCCH feedback still require a focused execution check.
Missing access-grid producers also make an occupied radio timeline appear
empty. Neither drawing synthetic grid rectangles nor dropping sounding
prerequisites is an acceptable repair.

See [the previous-run audit](continuous_iq_02_access_artifact_reaudit_20260913.md)
for exact CSV sources, indexing, IQ checks and measurement limitations.

## Mandatory unresolved gates, in repair order

1. **PUCCH power and feedback:** finish actual signal-present validation of
   the normalized repair, then qualify false-ACK and missed-ACK behavior jointly.
   The earlier independent two-bit noise check recorded 12/1024 false ACK bits
   (1.171875%); its execution success was not a detector qualification pass.
   Existing target-derived power-headroom fields also need explicit diagnostic
   versus physical applicability. Logical grant DTX flags were false while
   physical DTX and feedback outcome were true: repair their projection.
2. **Format-0 SR semantics:** the independent 14-case reference check fails
   TX in 12/14 cases and RX in 11/13 signal-present cases. Concatenating SR as
   HARQ changes cyclic-shift semantics, including the two-HARQ-plus-SR case.
   Fix transmitter `{HARQ,SR}`, receiver `[HARQ length,SR length]`, resource
   selection/validation and negative-SR-only no-transmission disposition
   together. This is separate from the HARQ-only power/noise defect.
3. **CSI-RS allocation:** enabled CSI-RS currently reserves REs outside its
   occasion. Add an absolute-clock checked occasion guard without disturbing
   TRS/ZP/SSB reservations. The existing focused case loses 12 RE (G 3060 vs
   3108); this is not an explanation for all throughput loss. Patch is blocked
   by the editor failure above.
4. **Control/HARQ continuity:** missed DL DCI still reaches
   `SharedDataDTXDispositionRequired`; add the proper receive-only observation
   disposition, then qualify shared retransmission/retained ACK/UCI chronology.
5. **Special slots and timing:** execute legal TDRA/K1/K2 allocation checks;
   reconcile RAR TA, TAG state, N_TA_offset, actual UL emission, propagation,
   channel filter delay, capture origin and independent residuals using delay
   perturbations across PRACH/Msg3/SRS/PUCCH/PUSCH. Do not infer perfection
   from a cropped receiver window or configured fixture timing.
6. **Measurement/beam closure:** CSI reference-domain and received-control
   repairs have component evidence, not exhaustive full-run qualification.
   Reconcile SS/CSI/PDSCH/PUSCH powers, noise and applied complex weights;
   qualify two-port UL TPMI at 12 dB, QCL/TCI runtime consumption, SSB beam
   evidence, RSSI/RSRP applicability and link-adaptation feedback chronology.
   Same TDD frequency does not force equal post-combining SINR with different
   spatial weights or measurement domains. No arbitrary 6/7 dB correction.
7. **Publication:** materialize actual RA-stage grids and SSB/data beam outputs;
   close missing alignment columns and historical snapshot contracts; verify
   all CSV/PNG lineage, constellation sampling and idempotent final rendering.
   The old 1,048 CSV / 1,373,809-row inventory and 292 decoded PNGs are file
   coverage, not independent verification of every measurement equation.
8. **One final baseline:** only after focused gates pass, commit/push qualified
   repairs, run one 58-slot baseline, audit terminal receipts/CSV/PNG/IQ/hash
   closure, document actual results and preserve a local Git bundle plus raw
   evidence (Git LFS objects are not contained in a Git bundle).

Approved two-port SRS/PUSCH, rank-one measured codebook selection, explicit
TDRA and QCL/TCI configuration remain in
`simulator/configs/scenarios/lls_causal_access_to_data_wiring_tdd_short_continuous_iq.yaml`.
The current physical fixture inherits this YAML; it is not a replacement
production profile. No full 58-slot run, testAll or E2E campaign was launched
at this checkpoint; the requested focused-test gate remains in force.

## Later capability qualification (not complete)

Keysight M9384B/M9383B playback and 89600 VSA demodulation; single-carrier
400 MHz at 7 GHz; 8 layers/two-codeword combinations; 1024-QAM UL and
4096-QAM DL where explicitly study-labelled; subsequent 30 dB validation.
Editable YAML does not establish support for every arbitrary configuration.
NTN/ISAC remain future work. Matching another implementation requires aligned
channel, reference plane, power normalization, numerology, receiver algorithms
and statistically adequate trials, not just the same nominal SINR.

## Reference basis

- [ETSI TS 38.213 v18.8.0](https://www.etsi.org/deliver/etsi_ts/138200_138299/138213/18.08.00_60/ts_138213v180800p.pdf):
  configured RA timing (8.2), HARQ/SR resource and cyclic-shift semantics (9.2).
- [MathWorks nrPUCCH](https://www.mathworks.com/help/5g/ref/nrpucch.html)
  and [nrPUCCHDecode](https://www.mathworks.com/help/5g/ref/nrpucchdecode.html):
  separate Format-0 HARQ/SR API payloads and expected lengths.
- [ETSI TS 38.104 v18.10.0](https://www.etsi.org/deliver/etsi_ts/138100_138199/138104/18.10.00_60/ts_138104v181000p.pdf):
  false-ACK reference definition; the component experiment is not conformance.
