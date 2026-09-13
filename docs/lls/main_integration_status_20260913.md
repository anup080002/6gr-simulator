# Main integration status — 2026-09-13

This supersedes current-status statements in the earlier candidate/handoff
notes. Historical evidence and patches are preserved, not rewritten.
The 12 dB baseline is **not yet qualified**.

Subsequent isolated checkpoint work and its bounded test results are recorded
in [received UL DAI and independent mapping](received_ul_dai_and_independent_mapping_20260913.md).
That work is not yet merged into the main revision being validated below.

## Consolidated and applied

Main was clean at `b03aed95`, then fast-forwarded to `06e534af`, retaining all
commits from both receiver and runtime branches. No stash existed. Both branch
tips are ancestors of main; checkpoint worktrees remain for evidence and the
still-running development suite. No files, output folders or branch refs were
deleted, and nothing was pushed remotely.

Three reviewed patches are now applied to source:

- `pending_sinr_limit_plot_provenance.patch`: CSV and plotted SINR retain the
  selected receiver field's status, reason, role, domain and raw diagnostic.
  Limited coordinates remain visibly labelled. No signal/noise power changed.
- `pending_12db_same_chain_sweep.patch`: the sweep inherits the exact
  continuous-IQ baseline and contains `[-30,-20,-10,0,10,12,20,30,40]`.
- `pending_received_harq_calendar_tests.patch`: five replay tests use the
  separately retained post-calendar-repair captures; original assertions are
  unchanged. Eleven previously omitted tests are registered in `testAll`.

Two new main-integration tests (sweep config and retained queue handoff) and
six additional existing feedback/scoring tests are also registered: received
DL feedback authority, received feedback outcomes, retained-ACK state/timing,
independent transmitted-DL expectations and CRC/scoring separation. Those six
additional registry entries still await the integrated mandatory batch.

The patch filenames are retained historical records, not an instruction to
apply them again. The three older CSI-RS/Type-2 patches were already applied
in `8cfac549`.

## Shared feedback handoff implemented, consumer still open

`commitReceivedDLHARQACKEvent` now runs at actual shared DL completion and at
the retained-ACK queue boundary. It binds the accepted shared control record,
private post-transition UE HARQ state and current physical sample clock.
It rejects mismatched/future control, wrong completion clock and duplicate
assignment commits. The typed event and availability clock are retained in
`SharedUEHARQACKEvents`, separate from `SharedDLHARQExpectations` at the gNB.
Retained ACKs do not generate a new decoder row or duplicate TB delivery.

This is **not** the completed UCI integration: the PUCCH/PUSCH builders and
received-bit disposition must still consume independent UE/gNB mappings.
Multi-assignment same-occasion, missed-DCI and wrapped-DAI shared-waveform
qualification remain required. No transmitted-feedback qualification is
manufactured by recording an event.

## Validation and preserved failures

- Integrated Python: **268 passed**, 13 dependency deprecation warnings,
  43.46 s. Includes SINR/radio/EVM plots, browser truth, exhaustive/deep-path
  audits, visual artifacts, uplink and SSB evidence, continuous IQ,
  large-scale power semantics and canonical PUCCH noise auditing.
  Receipt: `evidence_20260913/main_integration_python_01.xml`.
- First integrated focused MATLAB batch: **exit 1** in the new sweep test.
  Its initial whole-domain comparison wrongly rejected the intentional
  `canonical_control.launch.sweep_enabled` difference. The replacement
  comparison checks leaves with an explicit sweep/identity allowlist;
  simulation duration, seeds and PHY/impairment settings remain compared.
  Log: `evidence_20260913/sixgr_main_integration_focused_20260913_01.log`.
- Second focused batch also exited 1 in the new test: config provenance and
  generated fixed-link SNR aliases needed explicit treatment. Inspection of
  `localNormalizeFixedSNRSweepRunClass` established that these are normalizer
  mirrors, not changed PHY domains. The test now verifies each of those
  alias grids equals the exact nine authored values and ignores only config
  provenance/identity metadata when comparing physical configuration leaves.
  Its failed log is retained as `_02.log` beside `_01.log`.
- Third focused batch: resolved sweep check **passed**, nine points and 21
  permitted changed leaves, config hash
  `73bbbfcb449ff72baf183e500f1a1f20dc60f5e2f40c610f1874f278076d192a`.
  The entire 12-test focused batch subsequently completed with **exit 0** and
  `MAIN_INTEGRATION_FOCUSED_PASS`. Includes migrated replay, combining/report,
  QCL, disabled CSI, received event, retained shared-clock queue (nine guards),
  Type-2 layout/resource planning and both CSI calendar checks. Original log:
  `evidence_20260913/sixgr_main_integration_focused_20260913_03.log`.
  The queue test's pre-created output directory produces a nonfatal MATLAB
  directory-exists warning; it does not replace or erase earlier evidence.
  Required integrated `testAll`, config/LLS, export/grant/E2E and scenario
  suites remain to be completed on the frozen integrated revision.

The two superseded full suites were intentionally stopped after each had
four recorded failures: operator NSCID, geometry TDRA fixture, late PUSCH UCI
and late PUSCH CSI. Their fixes are preserved in the consolidated history;
earlier focused/guard passes do not convert those full-suite failures into
passes. These jobs are **stopped/incomplete**, not successful or timed out.
The intentional `regressionHarnessProbeTest` negatives are not added to the
four real failures.

Preserved original partial logs, independently matching SHA-256 at copy:

| Log under `evidence_20260913/` | SHA-256 |
| --- | --- |
| `stopped_sixgr_consolidation_full_20260913.log` | `6ff61e04da7fd2f9ebd4aa56d1f3e3686d391d4687d373ab3ab4b97e15a6aae6` |
| `stopped_sixgr_receiver_revision_full_20260913.log` | `4115a8a570aa7a63bd8ec1d8dd17437d3f0a0acecc57c79aa04cbbd89fd20424` |

The development full suite continues unchanged in its existing worktree.
It does not validate the newly integrated main-source changes.
Ignored output/cache directories and local environment files remain intact;
they are not silently deleted or added to a source commit. Clean Git status
will not imply that historical result folders have been erased.

## Remaining exit gates

1. Complete the received-event codebook and independent gNB UCI receiver
   integration; no row-index ACK mapping or borrowed UE payload length.
2. Qualify the PUCCH detector and independent Phase-05 evidence. The retained
   two-bit noise case still has 12 false ACK bits/1024 positions (1.171875%),
   above its configured 1% reference. No threshold or acceptance gate changed.
3. Close the timing, power/noise, measurement, CSI/SRS/beam causality and
   CSV/PNG/IQ acceptance matrix in `12db_measurement_closure_plan_20260913.md`
   using the new baseline's own raw evidence, not only auditor unit tests.
4. Complete mandatory integrated regression, commit the validated repairs,
   execute/audit the 12 dB baseline, then the same-chain sweep. The bounded
   58-slot baseline is neither a statistical BLER campaign nor an
   all-impairments scenario. Low-SNR decode failures remain legitimate data.

The NR-validation and result-integrity skills guided the separate evidence
ledgers and preservation of failures; the config-driven skill guided the
YAML-only sweep update and resolved-config regression.
