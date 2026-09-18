# Single-branch delivery and exact 400 MHz command

## Consolidation audit

Before this documentation update, `main` and GitHub both pointed to
`1ee2a5c2a0cfdb7d3f79b84cf2d524ade49d1007`.

- All 11 other local branch tips and all 10 other GitHub branch tips were
  already ancestors of `main`; no implementation merge was missing.
- Every registered historical worktree HEAD was also an ancestor of `main`.
  All seven extant checkouts, including the main checkout, had no uncommitted
  tracked or untracked changes before the README edit.
- Eleven annotated `archive/consolidated-20260918/<old-local-branch>` tags
  preserve the old local branch tips and were pushed before branch removal.
- The 11 obsolete local branches were removed with ancestry checks and safe
  deletion. The normalized-SSB branch's stale upstream was unset first because
  its extra commit was already in `main`, but not in that obsolete upstream.
- The 10 obsolete GitHub branches were removed atomically, using leases on
  their verified tip hashes. GitHub and the local repository now have only
  the `main` branch. Archive tags retain history without alternative branches.
- Fourteen stale Git worktree metadata entries pointed to already-missing
  checkout locations and were pruned. No actual checkout directory was deleted.
- Six clean detached historical execution checkouts, both recovery stashes,
  all local results, IQ files and logs are retained. They are preserved evidence,
  not active development branches. Existing stash/patch reconciliation is
  documented in `main_delivery_consolidation_20260917.md` and
  `pending_patch_reconciliation_20260916.json`; obsolete candidates were not
  reapplied over newer source.

## Exact operator command

The README section **Exact command: measured 400 MHz four-layer adaptive run**
contains a complete, standalone Windows PowerShell block. It selects the
default R2026a installation if present, otherwise R2023b, prints that choice,
runs focused preflight checks, generates missing same-version calibration,
then runs exactly:

`simulator/configs/scenarios/lls_7ghz_400mhz_adaptive_dl5_ul2_30db.yaml`

It names all log/result destinations, refuses to overwrite calibration, stops
on command failure, and prints the measured >6 Gbit/s condition separately
from payload delivery. The existing adaptive rank/QAM/rate policy is unchanged;
four layers were selected throughout the measured run, not forcibly locked.

All nine README PowerShell blocks passed PowerShell parser checks. Documented
scenario and setup paths exist; the three focused test entry points return
the boolean values asserted in the commands. `git diff --check` passed.
No new MATLAB scenario, calibration or `testAll` was launched for this
documentation-only delivery. R2023b whole-run qualification is still pending.

The retained R2026a outcome remains 5.926550 Gbit/s DL / 2.396846 Gbit/s UL:
payload delivery passed, >6 Gbit/s DL did not. Large generated artifacts remain
local, not in GitHub; the fresh-server command regenerates calibration and
creates its own results. See `research_dl5_ul2_outcome_20260918.md`.
