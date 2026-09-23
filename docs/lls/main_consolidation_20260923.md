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

## Follow-up consolidation after fb68e089

The next user-requested source checkpoint includes the subsequent receiver
error-classification and empty-data raster-authority repairs, with their
regressions. Configuration/capture errors retain their original identity
instead of being counted as ordinary SSB non-detection. Invalid NID2 lists
are rejected rather than replaced with a blind search. The raster root
guard accepts existing empty DL/UL schemas only with independent completed
clock and acquisition-outage evidence; it does not waive artifact coverage,
create data rows or qualify the run.

At review, local and remote `main` both pointed to `fb68e089`; there was one
branch and one registered worktree, with no divergent remote commits.
Historical reconciled stashes remain preserved, not reapplied.

Verification receipts checked for this follow-up:

- `logs/ssb_receiver_error_after_20260923.log`: all four focused tests passed,
  including invalid configuration/capture rejection, signal-present blind
  PBCH reception, detector-policy configuration and the eight-slot physical
  outage case. That last case retained four PBCH rows, 1,024 waveform rows
  and zero data trials; it is not an end-to-end sweep-publication pass.
- `logs/empty_primary_export_guards_20260923.log`: the previously running
  export and E2E truth/proxy batch has now completed with its final pass
  marker, superseding its running status in the earlier checkpoint above.
- `logs/outage_publication_guard_regressions_20260923.xml`: 279 Python tests,
  zero failures, errors or skips. A fresh precommit rerun is recorded in
  `logs/consolidation_publication_guards_20260923.xml`.

No new MATLAB suite or scenario is launched by this consolidation. The
existing eight-point sweep is left running. No `testAll` is started, per
the user's standing instruction. This remains a development checkpoint,
not full-regression, full-sweep or full-control 400 MHz qualification.
Generated outputs, logs and local environments are preserved under the
existing ignore policy; a clean Git working tree does not delete them.

## Follow-up consolidation after fcded09b

This checkpoint includes all six pending source/test files: strict no-data
chart applicability, actual SS/PBCH receive-window publication, command-line
coverage reporting, and the shared cell-search completion regression. It
does not generate constellation or data-BLER samples for unacquired links.
Receive-window charts explicitly do not claim decoded beam identities.

Local and freshly fetched remote `main` matched at `fcded09b` before this
checkpoint; there is one branch and one registered checkout. Both historical
integration commits remain ancestors, and their recovery stashes are kept.

Verification receipts:

- `logs/ssb_reception_chart_regressions_20260923.xml`: 296 Python tests passed.
  The consolidation rerun uses `logs/consolidation_chart_guards_20260923.xml`.
- `logs/cell_search_completion_error_20260923.log`: shared SSB preparation
  and completion assertions passed, including absent-producer and error identity.
- `logs/nr_phy_reference_guards_20260923.log`: configuration, strict proxy
  guards, DL, UL and reference-point batch completed with its final pass marker.
- `logs/no_data_chart_export_e2e_guards_20260923.log`: four export guards
  passed; the subsequent E2E campaign was still running during consolidation.

No new MATLAB run or `testAll` is launched. Existing sweep and E2E processes
are left untouched. Full sweep publication, detector statistics and full-control
400 MHz acceptance remain unqualified. Results, generated logs and local
environments are preserved locally, not force-added to GitHub. This is a
development checkpoint, not a claim that pending runtime issues are resolved.

## Follow-up consolidation after ea49b5b4

This user-requested checkpoint consolidates all ten pending source/test files:
Type-II wideband PUSCH report/count-field decoding, independently received
Part-1 sizing of Part 2, malformed-count rejection preserving independent
HARQ reception, and receiver-owned public DL/UL SINR provenance. The new
report regression is included with the existing component and waveform tests.
No scenario is silently switched to Type-II. Full measured Type-II report
generation and end-to-end shared-runtime qualification remain separate work.

Freshly fetched local and remote main matched at ea49b5b4 before staging.
There is one local branch and one registered worktree. The historical
cd397f33 and 471334ff integrations remain ancestors; their two recovery
stashes are preserved, not reapplied over subsequent fixes.

Verification receipts reviewed for this checkpoint:

- `logs/typeii_received_count_fields_v2_20260923.log`: 88 component cases,
  16 channel-codec cases and 16 toolbox matrix comparisons passed.
- `logs/typeii_received_report_waveform_20260923.log`: 24 typed-report
  coded-LLR cases, malformed-count handling, wire/report binding, received
  CSI Part-2 sizing and the physical Type-II PUSCH waveform test passed;
  the final `TYPEII_REPORT_AND_WAVEFORM_GUARDS_PASS` marker is present.
- `logs/public_data_sinr_provenance_20260923.log`: public DL/UL provenance
  cases and 66 receiver-SINR selector cases passed.
- `logs/public_sinr_semantic_guards_20260923.xml`: 130 Python tests, zero
  failures, errors or skips.
- `logs/public_sinr_retained_replay_guards_20260923.log`: replay preserved
  all 20 DL and five UL retained measurement values and their provenance;
  output coverage and the four export/integrity guards passed. Its subsequent
  E2E truth/proxy campaign is still running at checkpoint preparation; its
  final result is not claimed here.

No new testAll or scenario is launched for consolidation, following the
standing user instruction not to start testAll. The existing eight-point
sweep and E2E verification continue untouched. Full-regression, eight-point
publication and full-control 400 MHz acceptance are not claimed. The sweep
started before this commit and is not a frozen-revision run of this checkpoint.
Generated results, logs and local environments remain preserved locally under
existing ignore rules; they are not force-added to GitHub or deleted to make
the working tree clean.
