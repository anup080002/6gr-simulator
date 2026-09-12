# Connected QCL authority and DL CRC/scoring separation

## Root causes repaired

The main shared coordinator retained an actual received DCI capsule but did
not forward it to DL receive completion. QCL instead consumed a scheduler
grant decorated with payload-match and binding flags. The coordinator now
forwards `ReceivedAssignment` and explicit UE identity. Connected QCL validates
the capsule digest, installed context, received TCI codepoint/epoch and data
slot. It rejects the old scheduler-flag substitute for a connected profile.
Existing non-connected fixture compatibility is kept separate.

QCL references now retain the installed **RRC serving-cell index** separately
from the simulator's serving-cell index. Neither is inferred from PCI or
converted by an assumed one-based offset. The consumer checks both identities,
UE, source resource, configuration epoch, age, availability and sample clock.
The configured Type-A average-delay prior narrows DM-RS acquisition; the
receiver still measures its timing. This is not Type-D beam operation or full
Type-A Doppler/delay-spread qualification. The applicable association semantics
are in [TS 38.214 clause 5.1.5](https://www.etsi.org/deliver/etsi_ts/138200_138299/138214/18.08.00_60/ts_138214v180800p.pdf).

The legacy DL throughput runner also used equality to known transmitter bits
to override its CRC verdict, both initially and after combined decoding.
`scoreReceivedDLTransportBlock` now preserves the receiver's CRC decision and
computes payload bit errors separately. A decoded/reference length mismatch
is an explicit allocation/scoring-contract error, not a truncated comparison.
The reference payload cannot change ACK/CRC or trigger an extra decode.
Payload scoring remains available for integrity auditing; a CRC pass alone
does not certify error-free delivery. This preserves the receiver-owned HARQ
decision boundary in [TS 38.321 clause 5.3.2.2](https://www.etsi.org/deliver/etsi_ts/138300_138399/138321/18.01.00_60/ts_138321v180100p.pdf).

No YAML operating point, impairment, port count or noise normalization changed.
Existing YAML remains authoritative for TCI policy and timing-window radius.

The follow-up replay audit found unchecked snapshot clock semantics: the
DL/UL HARQ builders copied planning Frame/Slot aliases even after executing
the waveform. In the failing fixture these were zero-valued request/control
labels, not NaN (an earlier progress message incorrectly inferred NaN).
`bindExecutedHARQClock` now binds these fields
to the executed `nrCarrierConfig` and absolute data slot, including SFN wrap.
Finite contradictory scheduled times fail; they are not overwritten. The
snapshot's Frame is an NR frame, not a Monte-Carlo trial counter.

## Evidence

The first focused process exited zero:

- Actual saved received DCI and PDSCH/HARQ capture passed the new QCL boundary:
  window `[39,47]`, measured timing 43 samples and exact recovery of 1064 bits.
  Eight invalid capsule/clock/identity/future-source cases were rejected.
  Its QCL source values are an explicitly declared boundary fixture, **not**
  measurements from a real TRS transmission.
- Three saved decoder captures retained their original CRC decisions after
  complementing every scoring-reference bit. Error counts changed as expected;
  invalid TBS and missing verdict were rejected. No new transmission was made.
- Five regressions passed: shared QCL timing, YAML/QCL scenario contract,
  four-step received DL HARQ replay, QCL state propagation and receiver-owned
  combined DL decoding including CB-CRC corruption rejection.

The runner/shared-TRS regression process is tracked separately in the terminal
receipt; do not infer its result from the first process.

The actual shared-CDL TRS component passed: its received reference retained
RRC cell index 0 and simulator cell index 1, timing phase 7 samples and
availability sample 69120. Independent channel scoring compared 600 complex
pilot/branch values with NMSE -12.2123 dB. Its raw MAT capture is preserved.
This is a received reference producer test, not same-channel PDSCH/QCL or
main-scheduler HARQ qualification. The enclosing `_04` process still exited
one because its separate HARQ replay regression failed.

All intermediate failures are retained:

- The old data-only 11-RB HARQ fixture inherited an invalid SSB placement;
  it now excludes SSB/SIB1 explicitly, without altering production guards.
- Its runner call defaulted to absolute slot zero despite a K0-delayed
  scheduled data slot. The fixture now passes its scheduled data occasion.
- An allocation assertion originally obscured that earlier PHY clock crash.
  The fixture now saves the full result and checks for a crash first.
- The replay exposed preserved zero-valued request labels in the snapshot.
  The fixture now materializes and freezes a one-based data calendar before
  execution; production now rejects any conflicting snapshot clock.
- The new continuous-IQ TRS fixture initially omitted its required output
  root. It now supplies a unique local directory, without disabling IQ capture.

The earlier DL performance and execution-contract regressions passed even
though their enclosing batch failed the HARQ fixture. Final post-clock-repair
DL/UL/replay results are recorded separately in the receipt.

## Remaining integration work, not hidden by this checkpoint

Final focused results are now terminal: `dl_harq_replay_clock_20260913_06.txt`
exited zero for DL and UL replay. The missing symbol-allocation alias is
restored only from the frozen PHY grant and checked against the canonical
timing decision. The fixture also now serializes RV2 in its actual authored
DCI rather than retaining RV0 while requesting RV2 transmission. No production
RV consistency assertion was weakened. The final boundary/clock/QCL/CRC/RE/
TDD-and-FDD RA-continuation batch exited zero; its initial idempotence test
used NaN-unsafe `isequal`, corrected to `isequaln` with identical expectations.
All earlier failed logs remain retained. The artifact suite passed 248 tests.
See [receipt](evidence_20260913/qcl_crc_access_checkpoint_receipt.json) and
[new access/artifact findings](continuous_iq_02_access_artifact_reaudit_20260913.md).

1. The main DL runner still calls the older first-pass receive interface with
   TX-derived allocation/coding inputs. Forwarding the actual capsule for QCL
   does **not** complete UE-owned DL reception there.
2. The typed receiver's canonical output lacks reporting aliases consumed by
   the older main runner. Reuse or refactor the measured-evidence adapter with
   receiver-derived metadata before switching this path; do not fill missing
   fields with synthetic values. Keep current and combined decode domains clear.
3. Move main-run HARQ ownership into the UE entity and remove the runner's
   second combining pass. ACK-from-prior-decode requires a protocol-only
   completion, without a fabricated new PHY trial or duplicate delivery.
4. Dynamic DAI/monitoring-occasion Type-2 feedback and final shared-path QCL
   consumption still need qualification.
5. The disabled-power assertion in `testDataChannelStreamStages` remains
   unresolved: the mode-aware patch was refused by the edit tool again.
   No alternate write or ACL bypass was attempted.
6. Only after these gates: final 58-slot configured-12-dB run and complete
   CSV/PNG/IQ/manifests/terminal audit. Single-carrier 400 MHz/7 GHz, high QAM,
   30 dB, Keysight playback and long impaired runs remain downstream.

No `testAll`, E2E campaign or final 58-slot baseline was started. The user's
focused-test restriction is retained; no full-suite or full-conformance claim.

## Focused commands

```powershell
matlab -logfile dl_qcl_crc_authority.log -batch "setup6GRSimToolkit('Verbose',false); assert(testReceivedDLQCLAuthority); assert(testDLCRCScoringSeparation); runFocusedTests({'testSharedQCLTimingTransfer','testSharedQCLScenarioContract','testReceivedDLHARQReplay','testPDSCHQCLStatePropagation','testDLReceiverOwnedHARQDecode'});"
matlab -logfile dl_qcl_crc_runtime.log -batch "setup6GRSimToolkit('Verbose',false); runFocusedTests({'testLLS_DL','testLLSHARQGrantReplayTBConsistency','testDLPDSCHThroughputExecutionContract'}); assert(testSharedTRSChannelScoring('TDD',false,true));"
```
