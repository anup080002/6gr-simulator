# TDD shared-PUSCH focused completion repair

## Retained failing run

Revision: `3e2db7e1cf954de7bec6b6f2a189f5a9ab4944fa`.
Run: `logs/testall_20260914T103719589Z_ebf28fcb` (ZIP retained beside it).
MATLAB R2026a Update 4. Both focused tests failed; this is not a passing receipt.

- `testTDDSharedPUSCHIndependentCompletion`: real SS/PBCH timing and coded
  PUSCH reception executed; normal slot completion rejected the missing TB
  identity with `sixgr:truth:MissingRuntimeHARQTransportBlockIdentity`.
- `testTDDSharedPUSCHNonemptyCompletion`: configuration rejected enabled CRI
  reporting together with disabled CSI reporting before waveform execution.

## Root causes and scoped changes

1. `tests/testSharedPUSCHChannelArtifacts.m` creates its grants directly and
   bypasses the production `buildTrialContextFromGrant` new-TB identity
   assignment. A coding context can therefore exist with an empty TBId.
   The fixture now assigns the actual first frozen grant identity before
   encoding for the independent UL case and shared DL source. Added assertions
   join the executed TX ledger and retained RX context to that original ID.
   The production missing-identity assertion remains unchanged. No decoder
   result, payload, power, SINR, ACK/NACK decision or numeric limit is altered.
2. `lls_tdd_pusch_independent_empty_uci_fixture.yaml` explicitly disabled
   reporting booleans while inherited reporting-policy aliases could restore
   CRI for a descendant. Both YAML representations now explicitly disable
   reporting. The shared fixture verifies the resolved boolean and policy
   fields. Contradictory configuration remains an error; mixed CSI is not
   silently enabled or claimed qualified by these no-report tests.

## Acceptance and remaining scope

Rerun exactly `testTDDSharedPUSCHIndependentCompletion` and
`testTDDSharedPUSCHNonemptyCompletion` on a clean, frozen revision. Both must
pass; syntax checks and launching a run are not completion evidence.
The rerun verdict is pending at this commit.

Required final-source `testAll` and applicable NR/config guards remain due.
These focused tests do not qualify the full coordinator, missing-DCI handling,
mixed HARQ/CSI/SR, detector statistics, all measurements, the integrated 12 dB
scenario, other MATLAB releases, or the PHY sweep. FDD repairs remain deferred.

## Follow-up run on 29868472

`logs/testall_20260914T104600823Z_2941e075` again returned two failures.
The previous missing-TBId and contradictory-CRI checks were passed. The empty
case then failed on missing `LargeScaleState.BeamIndex`: the fixture discarded
the updated state returned by its first normal `applyUserContext` call. That
actual initialized state is now retained, not replaced by fabricated beam or
power fields. The nonempty case reached DAI preparation but lacked the runtime
serving-cell index, which is now bound from the actual DL user context before
DAI preparation. No physical loss or beam gain is injected to satisfy telemetry.
The next focused rerun is pending; neither case is claimed complete yet.

## Follow-up run on e5a169d2

`logs/testall_20260914T105101676Z_dcb8a6b4` returned one pass and one failure.
The empty-HARQ test passed, including normal completion, one actual UL TX,
zero DL HARQ updates and one common-commit receipt. The nonempty case decoded
its DL control but the fixture attempted to inspect an UL SRS field on DL DCI.
Its installed DCI context carries UL reference configuration even for a DL
message; that is not evidence that an UL-only field exists in that message.
The SRS-field assertion is now scoped to DCI 0_1, exactly like the adjacent
UL-precoding assertion. It remains required for the actual UL control.
Diagnosis will rerun the nonempty case, followed by both tests on the final
candidate. The combined task is not complete yet.
