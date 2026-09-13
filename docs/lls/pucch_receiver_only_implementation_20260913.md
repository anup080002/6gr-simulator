# Receiver-owned PUCCH allocation — isolated implementation checkpoint

Base: `b03aed95`. This implementation is in a detached worktree so the
original consolidation MATLAB suites can finish against unchanged PHY source.
It is not yet merged into the main checkout or qualified by a new full suite.

## Implemented path

- Added `PUCCHReceptionAssignment`: installed RRC resource, absolute receive
  slot, RNTI, length-only UCI context and explicit observation provenance.
  It has no UE power, spatial-application state or transmit payload dependency.
  Unexpected identity/context fields, unknown resources, changed epochs and
  RNTI mismatches are rejected. The exact report-context digest is bound.
- Exposed `PUCCHConfigBuilder.receiverConfiguration` to resolve installed
  resource configuration without constructing a UCI report or materializing
  UE transmit power.
- Wired the new assignment into the canonical `PUCCHReceiver.receive`.
  The existing transmission-assignment API remains available and is explicitly
  distinguished in receiver metadata. The new path checks the receive slot
  and context digest before demodulation.
- Changed `testPUCCHBaselineNoiseRF` to use that canonical path on actual
  physical-owner noise/RF observations. Its component-only evidence labels
  and false-ACK measurements remain; no conformance claim was added.
- Registered the two new receiver regressions in `testAll`.

## Verified regressions

`testPUCCHReceiverOnlyAssignment` replays hash-verified retained no-signal IQ,
including absent detections and observed false alarms for one/two HARQ bits.
Canonical detection metrics and decoded bits agree with direct Toolbox replay.
It also tests stale epoch/context, wrong receive slot, wrong RNTI, unknown
resource, payload-field injection and transmit-power-field injection.

`testPUCCHReceiverAssignmentEquivalence` executes actual standalone
transmitter waveforms for Formats 0–4 through both assignment APIs. Detection
metrics and decoded bits match exactly; decoded payloads equal the serializer's
bits. These are standalone fixtures, not full baseline or missed-DCI coverage.

The first equivalence run failed because `localSplit` returned a row-shaped
empty second sequence instead of the serializer's column-shaped empty vector.
The receiver now reshapes both decoded sequences to columns. The exact test
assertion was retained. The subsequent run passed all five formats.

Existing `testPUCCHResourcePlanningWithoutPower` and
`testType2HARQRuntimePlan` also passed in the initial component batch.
`testPUCCHPhase05` still failed at its unchanged
`sixgr:phy:pucch:UnverifiedPhaseEvidence` artifact-generation quarantine;
the other Phase-05 cases completed. The overall batch exited 1, not PASS.

Logs in the Windows temporary directory:

- `sixgr_receiver_only_component_20260913.log`: initial component batch, exit 0.
- `sixgr_receiver_assignment_equivalence_20260913.log`: empty-vector shape failure.
- `sixgr_receiver_assignment_equivalence_20260913_02.log`: equivalence passes;
  Phase-05 quarantine failure, exit 1.
- `sixgr_receiver_only_noise_20260913.log`: final negative/equivalence tests
  passed; the full 512-occasion physical-owner noise/RF component is running.

## Still required

The gNB scheduled-HARQ-expectation consumer is not implemented. Shared feedback
preparation still depends on decoded UE DCI/feedback rows. Creating this typed
receiver allocation does not claim that a missed-DCI receive window is armed,
that Type-2 expected-length hypotheses are resolved, or that its HARQ state is
updated from actual receive-only evidence. Those main-runtime steps remain
mandatory, along with Format-0 SR handling, detector qualification, timing,
measurement and CSV/PNG closure.

The retained two-bit noise-only false-ACK result exceeds its configured
reference; this patch does not tune its threshold or turn it into a pass.
The final 58-slot baseline and later long impairment-enabled, broad-feature
6G/NR work remain held by the unresolved gates.

Full `testAll` and the required E2E tests on this new revision remain pending.
The original main-checkout full/E2E processes are still live; they are not
evidence for the new receiver implementation. Memory pressure prevented
starting another concurrent full suite. Preserve the detached commit and
worktree until its validation and main-checkout integration are complete.

NR-validation and result-integrity guided keeping all strict guards, explicit
fixture scope, actual received-IQ authority and failure receipts intact.
