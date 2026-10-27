# P0 integration checkpoint — 27 October 2026

This checkpoint preserves the applied core MATLAB, YAML, reporting and test
changes. It is not a completed integration release. No new 60-slot scenario
was launched when the repository was consolidated.

The latest affected MATLAB batch completed with exit code 1: **23/26 passed**,
in 1,565.464 seconds on MATLAB R2026a Update 4. The original
[result JSON](p0_integration_affected12.json) retains every result, error
identifier and duration. The [source seal](p0_integration_affected12_source_seal.json)
records 6,237 files unchanged during that execution. It describes that test
interval, not subsequent documentation edits. The focused scope follows the
requested affected-test workflow; a full-suite pass is not claimed.

Before committing, all ten changed Python test modules passed: **406 tests**
in 19.68 seconds. They cover the affected codecs, CSV semantics, audit tooling
and radio measurement plots. Four MATLAB files received whitespace-only
cleanup after the sealed batch; their canonical text was checked unchanged.

| Remaining failed test | Observed failure | Next required work |
| --- | --- | --- |
| `testDRBRuntimeAdmission` | `sixgr:protocol:LineageViolation`: delivery refers to an unknown packet | Correct the fixture's foreign-runtime packet lineage and rerun the admission checks without bypassing original ownership. |
| `testSelectedPUSCHRetainedSSBRecovery` | Assertion on `pending.SourceSlot == 6` | Distinguish the gNB reference slot from the original UE measurement slot, retain both original records and rerun the complete physical recovery episode. |
| `testN40ReceivedMACControl` | `sixgr:protocol:MACFinalizationAuthority`: original received assignment and immutable TBS required | Repair the shared UL preparation/finalization handoff, then complete actual decoded SR/BSR/PHR and later scheduling checks. |

Passing this batch alone would not close every P0 item. The shared initial
access to common SRB1 transport, protected SecurityMode and dedicated bearer
activation paths remain incomplete. Received PHR allocation effects, reverse
RLC STATUS recovery and application delivery need accepted physical episodes.
The [open issue ledger](../lls_gap_status_20261023.html) retains that scope.

The original two-point run still has no accepted checkpoint60 or final-report
set. No 60-slot run was restarted during this recovery checkpoint.
R2024a execution remains unverified; this laptop's R2026a results do not
establish cross-release compatibility.

The subsequent report-verification scope explicitly leaves the three failures
open. Its [13 affected report checks](n40_report_launch_checks.json) passed
before launch. A fresh run is required to use the current scientific settings;
the old checkpoint55 retains different CSI, power-control and access settings.
No test assertion or runtime guard is disabled for that reporting run.

To repeat the same affected selection after repairs, from the repository root:

```matlab
setup6GRSimToolkit('Verbose',false);
receipt = jsondecode(fileread(fullfile('docs','lls', ...
    'n40_20261026_failure_review','p0_integration_affected12.json')));
result = testAll('Names', string(receipt.selected_tests));
assert(result.ok, 'The affected P0 test selection still has failures.');
```

Original logs, the full pre-test source hash map and unfinished drafts are
retained locally under
`E:\SixGRResults\diagnostics\n40_failure_20261026_slot58`.
The source log is `p0_integration_affected12.log`; the hash map is
`p0_integration_affected12_source_before.json`.
Unapplied work in `raw_srb_receiver_draft12`, `common_srb_grant_draft12`,
`shared_initial_access_draft12`, `protected_srb_transport_draft`,
`prach_bwp_draft12`, `drb_runtime_draft12` and
`selected_pusch_recovery_draft/batch12_receiver_reference_fix` is not integrated
or qualified by this commit. Preserve those drafts when resuming; compare
their baselines before applying changes to the committed code.
