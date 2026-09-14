# Single TDD integration codebase — 14 September 2026

This is an implementation checkpoint, not a qualified release or a successful
integrated 12 dB run. FDD repair remains deferred.

## Preservation and consolidation

Read-only ancestry checks against `b5712d7c826a842e08c00c4655babcb349a2ddd6`
confirmed that all nine existing local branch tips were already ancestors:
main, checkpoint/pucch-receiver-20260913, work/type2-runtime-20260913,
work/measurement-closure-20260914, work/shared-pusch-commit-path-20260914,
work/shared-pusch-completion-20260914, work/tdd-normalized-ssb-20260914,
work/tdd-detector-accounting-20260914 and work/tdd-sr-calendar-fixture-20260914.
There are no divergent commits on these branches to merge again.

The four other existing checkouts had no tracked edits or nonignored untracked
files. The remaining uncommitted implementation consisted of the two operator
master SR schedules and their contract test; these are included here.

All 13 tracked historical patch files remain preserved. Three use apply_patch
syntax rather than unified diff, and several older unified diffs no longer
reverse-apply after subsequent repairs. They must not be blindly reapplied.
The earlier semantic archive review is preserved in
`evidence_20260914/tdd_sr_calendar/` and `evidence_20260914/tdd_completion_clock/`.
That historical review and branch ancestry prove preservation/integration
history, not that every current behavior is correct or runtime-qualified.

No old branch, worktree, original patch, failed attempt or log was deleted.
Large ignored raw-IQ evidence and live logs remain in their original local
`logs/` folders; they are not claimed uploaded merely because source is pushed.
The published detector commit `104e13f1` and all three live suite HEADs are
unchanged. Future implementation proceeds on `integration/tdd-12db-20260914`.

## Additional operator-master SR repair

Both self-contained TDD operator masters omitted the catalog field
`pucch_resources.scheduling_request_resources`, although they listed SR
resource 0. The existing contract test stopped at this omission.

Both now explicitly author SR configuration 1 / SR ID 0 / resource 0 with
period 10 slots, zero-based offset 4, priority 0 and no additional-periodicity
capability. This is an editable operator choice, not a universal 3GPP value.
Their 30-kHz, five-slot TDD pattern has three DL slots, a mixed slot with
only one UL symbol, and one full UL slot. The two-symbol Format-0 resource
therefore fits the chosen full-UL occasions; copying the 15-kHz diagnostic
fixture's offset 3 would place it in the wrong slot. A five-slot SR period
at 30 kHz would require additional capability under the installed catalog;
the authored ten-slot period does not.

The original `pucch_resources.enabled: false` flags remain false. The repair
completes configuration; it does not silently enable a PHY feature, create
positive SR bits, execute MAC SR lifecycle, or install this policy into the
separate 58-slot production 12 dB scenario.

The contract test additionally checks exact config propagation, complete
resource coverage, catalog/capability compliance and nominal UL-symbol fit.
Negative mutations cover a mixed-slot offset, undeclared extra capability
and an empty calendar. No primary RF rows or fabricated results are emitted.

## Verification and next execution

Executed pre-runtime checks: native MATLAB static analysis (no syntax errors),
git diff whitespace checks, and independent Python authored-YAML/slot algebra
for both masters. The Python check rejected all three negative mutations for
each master and confirmed that removing the new schedule restores the entire
previous YAML tree exactly. It is not the normal MATLAB loader or PHY runtime.

Still required on this committed integration source:

1. Focused `testConfiguredSRCalendar` and `testOperatorMasterConfigurationContract`.
2. Detector accounting/config/physical candidate checks; held-out detector
   campaign and unchanged confidence gates. No detector qualification yet.
3. Remaining mixed HARQ/CSI/SR, missing-DCI and CSI source-authority repairs.
4. Full unfiltered `testAll`, applicable NR/config/strict/scheduler/export/E2E
   and scenario skill guards. Parent-suite results do not qualify this child.
5. Integrated 12 dB execution and all-measurement/CSV/PNG audits, then the
   retained same-chain sweep [-30,-20,-10,0,10,12,20,30,40].

All three existing laptop suites remain running by user instruction. New
MATLAB work must wait for sufficient capacity or execute on the second server.
