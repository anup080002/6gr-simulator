# Main source checkpoint, 23 September 2026

This is a user-requested development backup and consolidation, **not a
qualified release or an eight-point/400 MHz acceptance claim**.

## Preservation and reconciliation

- Before this checkpoint, local `main` and `origin/main` both pointed to
  `884d3643ce4910da4dc8d8d492e186a433d061c3`. GitHub and the local repository
  each have only the `main` branch. No alternative branch merge is required.
- All current tracked edits and untracked source, tests, YAMLs, tools and
  documents are included together. No reset, source replacement or squash
  of historical commits was performed.
- Six obsolete registered checkout locations no longer existed. Their tips
  (`15aa291c`, `91046b23`, `6be2985f`, `68140bb9`, `cef38516`, `3f0ed1e4`)
  were verified to be ancestors of main before pruning only Git's stale
  worktree metadata. The main checkout is the only registered worktree.
- Both historical recovery stashes remain untouched. Their reconciliation
  is recorded in `main_delivery_consolidation_20260917.md`; the integrated
  commits `cd397f33` and `471334ff` were again verified as ancestors of main.
  Reapplying those stashes would reintroduce superseded source.
- `pending_browser_row_lookup_20260922.patch` reverse-checks successfully
  against current source: its implementation is already integrated.
- The four non-runtime files in
  `pending_receiver_export_and_mat_publication_20260922.patch` also
  reverse-check successfully. The runtime portion has subsequently evolved;
  source inspection confirms receiver-owned widths/digests, both decoded
  sequences, CRC applicability, actual receiver usability, no-producer
  success exclusion and proxy quarantine remain integrated. Do not reapply
  the old patch over the newer standalone-SR and independent-capture work.
- Historical patch documents are retained as evidence, not alternative
  runnable implementations. Generated `results`, `logs`, temporary data,
  local dashboard settings and environments remain local under existing
  ignore rules. No run evidence was deleted or force-added to GitHub.

## Verification boundary

Existing local receipts at consolidation time:

- `logs/empty_primary_schema_v2_20260923.xml`: 210 Python tests passed for
  primary-table materialization, applicability, sparse evidence, exact
  constellation sources, applied-beam evidence and CSV semantics.
- Dashboard discovery regression: 12 Python tests passed, including discovery
  of a real sweep child before the parent has a terminal manifest.
- `logs/strict_pdsch_noise_after_v2_20260923.log`: five focused MATLAB tests
  passed for strict PDSCH execution, occupied-RE AWGN, standalone reference
  energy, HARQ-probe noise and physical eight-point noise isolation.
- `logs/empty_primary_export_guards_20260923.log`: four export/integrity
  guards passed; its subsequent E2E tests were still running when this
  checkpoint was prepared. Do not infer their final verdict from this note.
- `logs/sweep_failure_policy_integration_20260923.log`: earlier export/E2E
  and scenario-matrix integration batch completed successfully.
- `git diff --check` passed before staging. The staged check passes for
  source/config/tests/documents except the two preserved `.patch` files:
  Git flags their required single-space blank context lines as trailing
  whitespace. Those historical patch bytes were intentionally preserved.
  No new `testAll` was launched,
  following the user's explicit instruction. Full final-source regression
  qualification is therefore not claimed.

## Actual run state, not acceptance

The retained saturated 5 MHz / 20 dB v10 run completed all 58 slots and its
functional required checks. That does not qualify detector statistics,
long-run stability, Type-II CSI transport or all operating points.

The active eight-point v12 sweep uses
`lls_tdd_5mhz_rank2_shared_awgn_snr_sweep_saturated.yaml` and the configured
points `[-30, -20, -10, 0, 10, 20, 30, 40]`. At this checkpoint it had moved
from -30 dB to -20 dB. The -30 dB point completed physical slots without
acquisition/data grants and recorded a terminal publication failure. It is
not a passing data-link result. Correct per-artifact handling of genuinely
unavailable measurements versus missing exports remains unresolved.

The active run began from a dirty source tree before this commit; the new
commit must not be retroactively represented as its frozen launch revision.
Neither that run nor the already-running focused E2E batch was restarted,
stopped or edited by consolidation. Full-control 400 MHz acceptance,
statistical detector qualification, paired-rank campaign quality and complete
Type-II CSI wire/runtime integration remain separate open work.
