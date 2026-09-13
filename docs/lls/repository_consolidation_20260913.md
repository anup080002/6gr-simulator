# Repository consolidation — 2026-09-13

## Saved work and branch audit

Before consolidation, HEAD was `7854dcbf` on `main`. All 51 commits dated
September 11–13 were already reachable from this branch: 3 on September 11,
22 on September 12, and 26 on September 13. Tracked source, tests and configs
matched HEAD. There was one local branch, one worktree, no stashes and no
uncommitted changes. No branch merge, reset, squash or recovery was needed.
The local branch was 19 commits ahead of the locally recorded `origin/main`;
no remote fetch or push was performed for this audit.

## Previously blocked patches integrated

All three saved patches applied successfully after the laptop restart:

- `pending_csirs_planner_calendar.patch`: normalize character/string channel
  selectors before reshaping, and resolve CSI-RS against each absolute slot's
  runtime calendar instead of reusing the initial slot's configuration.
- `pending_type2_harq_consumers.patch`: preserve typed HARQ codebooks through
  PUCCH resource planning with an epoch check, and map exported bits to their
  observed source events without inventing identities for DAI gaps.
- `pending_type2_vector_manifest.patch`: bind the two corrected HARQ CSVs to
  their actual SHA256 hashes and explicitly label their bounded oracle scope.

The original patch files are retained as historical records, not outstanding
patches to apply again. The earlier editor-block reports describe the state
at their checkpoint; this note supersedes their unapplied status for these
three patches only. No other implementation or qualification gate is closed
by this consolidation.

## Validation

Verified so far:

- `git diff --check`: passed.
- `python -m pytest tests/test_type2_harq_vectors.py -q`: 10 passed.
- `python tests/vectors/pucch/verify_pucch_vector_pack.py`: 31 manifest files,
  4,271 vector rows, no failures.
- MATLAB focused HARQ batch: exit 0; `testType2HARQACKLayout`,
  `testPUCCHResourcePlanningWithoutPower`, and `testType2HARQRuntimePlan` passed.
- `testCSIRSPlannedCalendar`, `testConfig`, `testStrictProxyGuards`, and
  `testStrictMode_NoFallbackAnywhere`: passed in the additional guard batch.
- `testPUCCHPhase05`: failed at artifact generation with
  `sixgr:phy:pucch:UnverifiedPhaseEvidence`. The pre-existing fail-closed
  quarantine requires execution-backed independent-vector, DMRS correlation,
  hopping comparison and spatial application evidence. It remains intact.
  In particular, the phase exporter change is not qualified by an artifact run.

Full `testAll` and the additional LLS/export/grant/E2E guard batch were launched.
Their completion status is pending; no full-suite PASS or full-simulator
qualification is claimed. MATLAB logs are outside the repository in the
Windows temporary directory:

- `%TEMP%/sixgr_consolidation_focused_20260913.log`
- `%TEMP%/sixgr_consolidation_guards_20260913.log`
- `%TEMP%/sixgr_consolidation_full_20260913.log`

The NR-validation and result-integrity skills guided preserving typed event
identity, truthful manifest provenance and the existing evidence quarantine.
No assertions were weakened and no fallback or proxy rows were added.
