# TDD missed-UL-DCI: receive-only capture foundation

This is a bounded implementation/validation checkpoint, not closure of missing
DCI, shared feedback, or the 12 dB scenario. FDD-focused repairs remain deferred.

## Confirmed root causes and changes

`runWaveformLinkBundle.m`, `localCompleteSharedScheduledPDCCH`, still cancels an
unexecuted UL HARQ allocation and returns after rejected UL control. No gNB
PUSCH receive window is installed on that branch. Existing `queueData` requires
a `PreparedDataTransmission`; using it would wrongly require a UE waveform and
TB when the UE did not accept the grant.

`CoupledWaveformStream.queuePUSCHReceiveOnly` now registers only the actual gNB
pre/post-RF windows. It checks scheduled UL geometry, grant/UE/RNTI and sample
clock identity, rejects incomplete and duplicate windows and conflicting
prepared/executed transmissions, and retains registration identity after
completion. It neither enqueues IQ nor creates a TX commit, TB or decoder result.
The completion dispatcher counts two receive planes, not a fabricated third TX
plane. The normal coordinator does NOT call this new primitive yet.

The new regression exposed a separate production defect: a retained integer
slot ordinal made `advanceSlot` combine integer scalars with double OFDM index
arrays (`MATLAB:mixedClasses`). The stream now validates the positive, exactly
representable slot and uses double internal OFDM indices. The test keeps the
integer-typed ordinal; it does not cast away the failing stimulus. No physical
clock value, RF/noise/power policy, receiver threshold or assertion was relaxed.

## Executed evidence

R2026a Update 4, integration checkout based on `2d68992a`, with the explicitly
reported working-tree candidate changes (`AllowDirty`, not frozen-source proof):

| Run under `logs/` | Result |
| --- | --- |
| `testall_20260914T181946600Z_466e3a00` | New capture test failed at mixed-class OFDM arithmetic; original failure and ZIP retained |
| `testall_20260914T182256607Z_bbc8be3e` | Capture test PASS 90.16 s; existing transmitted-data queue test PASS 96.12 s; MATLAB/launcher exit 0 |

The new test uses the existing TDD component YAML and a retained scheduled UL
grant, not a newly decoded DCI. It executes the shared CDL/RF/noise owner, checks
one complete capture and two receive planes, zero DL/UL HARQ TX counts, no data
transmission ledger rows, no feedback producers and duplicate/window/identity
rejection. It performs no PUSCH decoder attempt or missed-DCI-rate measurement.

Raw local artifact:
`logs/tp9c1ca49d_7ca8_46bd_9373_4078d9d9bcf7/receive_only_capture.mat`.
Size 33,657,854 bytes; independently computed native SHA-256:
`dee7e8e99a6e217e42b5d7194d00520bb47034bc24bc3d8920538828c4c40e3c`.
This digest binds the saved bytes; it is not independent PHY qualification.

The still-running frozen `5debd387` suite separately passed both existing empty
and nonempty independent shared-PUSCH completion tests (140.49 s / 226.36 s).
Its log is `testall_20260914T165711543Z_51e8a47f/matlab.log`; the nonempty case
recorded one real DL TX, one UL TX, one common receipt and actual ACK=1.
Those passes do not establish the unimplemented receive-only coordinator path.

## Next implementation and acceptance boundaries

1. In `runWaveformLinkBundle.m`, schedule gNB receive ownership from the issued
   UL grant independently of UE acceptance. On rejected control, retain the
   actual rejection and cancel only the unsent UE HARQ allocation. Derive the
   capture window from installed gNB timing/search policy, not UE TA or a fake
   prepared object. Reject receiver crashes as failures, not measured DTX.
2. Add a receiver-only PUSCH completion adapter. Use the actual completed
   post-RF observation, scheduled frozen coding/TBS/RV/original-MCS authority,
   `buildSharedPUSCHUCIReceiveContext` and installed CSI schema with `PUSCH_Rx`.
   Do not pass `ExpectedUCIPayload`, invent a TB/CRC, or substitute a DTX result
   without decoding. Validate observation provenance and acquired timing.
3. `completeSharedPUSCHHARQFeedbackRuntime` currently joins transmitted producer
   metadata. A no-TX path must use the common independently scheduled feedback
   commit without manufacturing TX scoring fields or producer rows. Resolve
   PUCCH/PUSCH ownership before commit; one DL obligation must not update twice.
4. Add actual rejected-UL-DCI normal-path tests, then leading/interior/trailing
   and all-missed DL DCI (including 4/8 assignments), wrap and mixed HARQ/CSI/SR.
   Check independent receive widths, duplicate/stale/late feedback, actual
   receiver outcomes, no phantom TX/goodput/EVM/BER rows and CSV provenance.
5. Run clean frozen-source focused capture/transmitted-data/shared-PUSCH tests,
   all archive checks, full `testAll` and the required NR/config/export/E2E
   guards. The older suites cannot qualify this newer source. Final detector,
   measurement/export and integrated 12 dB acceptance remain outstanding.

The not-yet-started archive-only queue was superseded before MATLAB launch at
18:27:54 UTC. Its status and supersession receipt remain under the archive
validation checkout's `logs/archive_validation_queue_01/`. Neither running full
suite was stopped. A newer frozen-source validation queue replaces that work.
