# TDD detector accounting candidate - runtime verification pending

Parent: frozen `e6341805`, whose full regression is running in the IDE
checkout. This patch is isolated in `sixgr_detector_accounting_20260914`;
no live suite source or HEAD was changed.

## Confirmed gaps and repairs

- `validatePUCCHDetectorPilotPolicy.m`: require exactly the two noise-width
  hypotheses and all six signal payloads. The old runner accepted duplicate
  payload hypotheses under eight distinct names. Reject unsafe evidence
  filenames, duplicate IDs/slots and episode seed overflow before any output
  directory or RF execution is created.
- `countPUCCHDetectorPilotErrors.m`: export actual receiver usability,
  actionable false ACKs, missed ACKs, NACK-to-ACK errors, signal-bit errors
  and their explicit opportunity counts. Erased signal bits count as errors.
  Preserve the existing conservative noise event gate on any raw ACK bit,
  even if the receiver rejects that payload; expose RawNoiseACKBits separately.
- `runPUCCHDetectorPilot.m`: call these helpers, append counts to physical CSV
  rows and reject duplicate receive rows within an episode. Eight total rows
  cannot substitute for eight distinct required cases.
- `testPUCCHDetectorPilotAccounting.m`: declared-input positive/negative
  fixtures, boundary seeds, CSV roundtrip and comparison against the eight
  previously retained physical receipts and independent audit counts.
  Registered in unfiltered `testAll`.

Detector implementation, threshold 0.42, authored seed schedule, RF samples,
confidence policy and episode count are unchanged. This is not a fix or a
pass for the retained 12/1,024 false-ACK failure. The runner remains
development-only and always declares DetectorQualified=false.

## Required execution

1. Focused `testPUCCHDetectorPilotAccounting`, then actual
   `testPUCCHDetectorPilot`; inspect new CSV fields against the saved MATs.
2. Full unfiltered `testAll` on this frozen candidate, plus required explicit
   NR, E2E and result-integrity guards.

At patch preparation, three actual MATLAB workers were live (21968, 23964,
3424). No fourth worker was launched. Static diff checks are not runtime
verification; the running parent suite cannot qualify these new edits.

The installed R2026a standalone Code Analyzer was executed on both helpers,
the accounting test, pilot runner and testAll. No syntax errors were reported.
The pilot/testAll retain advisory dynamic-growth/style diagnostics. This
static check does not execute MATLAB assertions or physical reception.

Still required for detector acceptance: frozen receiver-policy development,
explicit development/held-out seed separation, a held-out campaign runner,
independent physical episodes and unchanged confidence gates. Exact pilot
coverage and bounded seeds do not prove independence or qualification.
