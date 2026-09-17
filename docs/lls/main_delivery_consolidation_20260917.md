# Single delivery branch: main, 17 September 2026

This is a source-preservation and operator-documentation checkpoint, **not a
qualified release**. The 10.5 GHz study and bug fixes are deferred by request.

## Source reconciliation before delivery

- All 12 local branch tips, including the prior `main`, are ancestors of
  `04364b70a3b64a96e0471a63e705e25530afa9f5`. Every extant registered worktree
  HEAD is also an ancestor. No committed implementation is waiting on a
  separate branch merge. Delivery fast-forwards `main`; it does not squash
  history or overwrite remote history.
- The only dirty historical worktree is
  `sixgr_tdd_combined_receiver_20260916`, based on `08f9ec60`. Its 13-file
  candidate was compared with the integrated `cd397f33` tree. Ten files have
  identical Git blob hashes, including every modified production file and
  the new `normalizeReceivedPUSCHCSI.m` helper and CSI fixture YAML.
- Of the remaining three files, `testPUCCHConfiguredSRResource.m` differs
  only by a trailing blank line. The old `testAll.m` omits two BSR tests that
  the integrated tree includes. The old `testSharedPUSCHChannelArtifacts.m`
  has the superseded CSI timing assertion; the integrated version verifies
  the UE audit record separately from fields actually carried on received
  CSI UCI. Replaying these old files would revert newer work. No unique
  production edit was found in that snapshot.
- Both recovery stashes are retained. The recovery stash's changed source
  files are present at `471334ff`; the BSR candidate is included in
  `cd397f33` with the subsequent preparation-identity repair. Neither stash
  is blindly reapplied. Historical snapshots remain available locally.
- The six top-level pending patches were already reconciled in
  [the retained patch receipt](pending_patch_reconciliation_20260916.json).
  Patch/archive files remain historical evidence, not a second runnable
  implementation. No logs, IQ data, stashes, or worktrees are deleted here.

## Runtime and acceptance boundary

The README and runbook changes do not modify MATLAB, Python, runtime YAML,
receiver settings, detector gates, noise, transmit power, or assertions.
The executable simulator source and runtime configuration match the selected
capture/regression revision `6be2985f`; subsequent commits contain documents
and evidence, including separately located read-only evidence scripts.

The 400 MHz capture completed 30/30 DL and 40/40 UL TBs with exact payload
checks. Its 10 ms TDD goodput is 1.868280 / 2.491040 Gbit/s, using two layers,
1024-QAM and rate 0.82. This is best among the tested rates for that fixed
lab configuration, not a global optimum. Large IQ files remain local under
`logs/`; GitHub carries the implementation, YAMLs, instructions and small
receipts. Actual Keysight import and R2023b qualification are not established.

The separate 5 MHz / 12 dB run completed physical execution but **failed**
integrated acceptance and report finalization. See its
[terminal outcome](tdd_5mhz_12db_68140bb9_outcome_20260917.md).

The selected-source unfiltered `testAll` remains running. As of approximately
22:00 IST, it recorded five failures: `testResearchTDDLink`,
`testSharedUnselectedPUCCHProducer`, `testSharedCSIReportClockVariants`,
`testFutureULPlanningCausality`, and `test6GMandatoryStudyPackScenarios`.
No full-suite pass is claimed. The three superseded suites were stopped with
explicit user approval and their logs preserved as interrupted. They are
not passing suites. The selected running checkout is not edited by delivery.

The repository requires unfiltered `testAll`; its current incomplete/failing
execution remains an open qualification item, not waived by documentation
checks. README commands also provide the existing logged server launcher.
