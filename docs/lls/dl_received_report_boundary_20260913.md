# Received DL report boundary checkpoint

This checkpoint prepares the UE-owned DL receiver for the main shared-runner
handoff. It does **not** qualify that handoff or release the final 58-slot run.
The final guard is **failing**, and the allocation repair below is blocked by
the file-edit tool. This is an unqualified local preservation checkpoint.
The 12 dB YAML operating point, two-port SRS/PUSCH, channel, RF settings and
antenna geometry are unchanged.

## Repairs

- `ReceivedDLHARQState.receive` passes the actual received DCI capsule to the
  typed PDSCH receiver's reporting boundary. The report reconstructs its
  allocation from installed configuration, received control and retained UE
  coding history. Assignment digest, resource plan, coding plans, references,
  carrier and receiver configuration must match the executed typed inputs.
  No transmitter TB, matrix, injected-noise oracle or scheduler coding plan
  is admitted through this boundary.
- The existing report adapter now labels connected received-control ownership
  explicitly. It reports the same canonical decode; it does not run a second
  LDPC decode. A missing capture timing contract fails before decoding.
- Current-attempt rate-recovered LLRs previously aliased `HARQCombinedLLR`.
  They now come from `Decode.RateRecoveredLLR`; combined LLRs have separate
  fields and explicit domains. `CurrentAttemptStandaloneCRCMeasured` says
  whether the actual decoder used no prior HARQ combination. A combined CRC
  is not an independently measured current-only CRC.
- Invalid canonical decoder noise is rejected, not replaced with epsilon and
  reported as a valid measurement.
- CSI-RS receive reporting uses the received data-slot configuration and the
  same installed periodic calendar as TX. The reference kernel uses an
  always-on local resource configuration, so calling it without an occasion
  gate would inspect non-occasion REs. `csirsOccasion` now owns that shared
  arithmetic. The resolved CSI-RS configuration is retained in the report.
  Calendar eligibility alone is not proof of signal reception.
- When no absolute runtime slot is supplied, TX calendar lookup now includes
  the carrier frame, instead of restarting the calendar at every `NSlot` wrap.

No new scenario policy or RF setting was hardcoded. The existing YAML
`phy.csirs.period_slots`/`offset_slots` internal values remain authoritative.
The scalar calendar helper validates arithmetic; legal standardized resource
profiles still belong to configuration validation.

## Focused verification

`received_dl_report_adapter_02.txt` records a zero-exit MATLAB batch containing
received HARQ replay, QCL authority, typed facade delegation and exact CSI-RS
reservation tests. The earlier adapter log also passed its replay/QCL tests.

The first new report-evidence test failed because it demanded equality of
recorded and replayed `tic/toc` decoder durations. The revised test compares
every other decoder field exactly, plus canonical metrics and equalized
symbols. It separately requires finite positive newly measured durations,
matching report aliases and the actual instrumentation source. The failed log
is retained, not overwritten. The follow-up result is recorded in the terminal
checkpoint receipt; do not infer success from this description.

The first follow-up passed the report test but stopped on an incorrect batch
invocation: the no-output noise-contract test was wrapped in `assert(...)`.
The next invocation executed that contract but only constructed the two
`functiontests` suites. Neither batch qualifies their unit-test bodies. The
subsequent batch used `runtests` and `assertSuccess`: three AWGN/MIMO cases
passed, followed by the report replay, with terminal exit zero.

A disabled-CSI fixture also initially retained the baseline's strict CSI
requirement and correctly failed `sixgr:mimo:MissingMeasurementState`. The
final guards test that rejection explicitly, then separately test an
optional-CSI fixture with its requirement disabled. No production guard or
baseline YAML setting was weakened. All failed attempts are retained.

That optional fixture exposed a genuine additional defect. The diagnostic
reports `status=disabled`, no CSI-RS indices and no CSI-RS observation, but ACK
and delivery differ from the archived non-occasion capture. Inspection found
that `allocREsPDSCH.localReserveCSIRSResources` unconditionally invokes the
always-on CSI-RS reference kernel whenever CSI-RS is enabled. Thus historical
PDSCH captures contain rate-matching holes even outside CSI-RS occasions.
Disabling CSI-RS removes those holes and changes the receiver mapping; the old
capture cannot honestly be decoded against that changed mapping. The test
remains failing; neither its ACK comparison nor production guards were relaxed.

The required repair is to apply `csirsOccasion(cfg, absoluteSlot0)` before
CSI-RS reservation in `+sixgr/+phy/+grid/allocREsPDSCH.m`, using the same absolute
clock as transmission and reporting. Two `apply_patch` attempts failed with
`Failed to write file`. Read-only diagnostics showed `IsReadOnly=False`; the
precise tool/filesystem write restriction has not been established. No ACL,
ownership, alternate-write or configuration workaround was applied. The
allocator is unchanged. No test/capture generation from the rejected multi-file
patch ran.

After restoring write access, add off-occasion and frame-boundary capacity
regressions, then generate a **new separately named** four-attempt component
capture set with the corrected allocator. Keep the old captures and logs as
historical evidence; do not overwrite them or relabel them corrected. Update
the active replay fixtures only to the newly executed captures, rerun report,
HARQ/QCL and noise-domain tests, and then continue the main handoff. The current
failed optional-CSI comparison cannot be certified away by changing a status
label or forcing an ACK.

These saved data captures are non-CSI-RS occasions. The calendar and disabled
cases are covered here; actual CSI-RS-on-occasion received-control reporting
still needs an appropriate waveform integration test before the main handoff.

Only focused tests are run under the active task's scope. `testAll`, E2E
campaigns, a new full 58-slot run and instrument playback are not qualified by
this checkpoint. Replayed captures retain their original provenance.

## Main handoff remains mandatory

The production shared coordinator still needs to persist one UE DL HARQ entity
per UE and pass it through receive completion. The connected branch in
`runDLPDSCHThroughput` must stop supplying TX coding arguments and stop its
second combine/decode. The decoder/report boundary above is ready for focused
integration testing, not evidence that those callers have changed.

The same integration must handle already-decoded repeated assignments without
fabricating a new PHY trial, and failed DCI as a control/DTX disposition without
decoding from scheduler knowledge. Received DAI, actual UCI transmission and
feedback reception must remain causal. Updating a local ACK decision is not
proof of a transmitted or received PUCCH/PUSCH ACK.

The prior measurement/artifact audit remains applicable, including the open
applied-matrix beam-pattern provenance, downstream RA resource-grid producers,
special-slot dispatch, independent TA/synchronization perturbation checks,
historical snapshot contracts and repeated-rendering investigation. See
[the access/artifact re-audit](continuous_iq_02_access_artifact_reaudit_20260913.md).
None of these is closed by a decoder replay. Single-carrier 400 MHz / 7 GHz,
eight-layer/two-codeword, extended QAM and Keysight playback qualification remain
downstream work, not proven by editing YAML alone.
