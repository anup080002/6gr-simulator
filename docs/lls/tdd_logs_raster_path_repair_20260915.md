# Repo-local logs raster publication repair

Unqualified integration checkpoint, prepared in an idle checkout while the
12 dB PHY run remains frozen at 2c45b257. No active MATLAB source was edited.

## Authoritative failure and root cause

The retained `tdd_5mhz_12db_5689ed33_20260915` publication receipt at
`published/browser_publication_receipt.json` reports materializer exit 1:
`Refusing raster replacement outside trusted run roots`. Its only trusted
root was the checkout's `results/lls`; the actual requested run lives under
`logs/scenario_runs/lls/<scenario>/<run>`.

The MATLAB results-root resolver already admits repo-local logs. The Python
publisher's `validate_run_root` did not, so its strict invocation stopped
before materialization and no `contract_plot_lineage.csv` was produced.
The outer recovery loop subsequently reported TerminalArtifactFixedPointFailed.
That later message did not identify this original path-authority mismatch.

## Change and preserved gates

`scripts/regenerate_lls_rasters_from_csv.py` now admits canonical repo-local
`logs` as well as `results/lls`. Both still require at least two descendant
segments and the existing resolved-config, identity, summary and applicable
nonempty primary-CSV authority checks. Siblings and paths resolving outside
the permitted roots remain rejected. No synthetic rows, placeholder PNGs,
hash bypass, power change or acceptance-threshold change is introduced.

This does not make an aborted run with empty primary data eligible for
normal plot publication. Its missing evidence must remain explicit. Do not
claim the complete recovery/finalization problem solved from the path test.

## Tests executed on Windows / Python 3.12.4

Logs are in `sixgr_archive_validation_20260914/logs`:

- `raster_logs_guard_before_20260915.xml`: 4 failed, 3 passed. Both intended
  logs leaf paths were rejected before the repair; two broad-directory
  tests observed the earlier outside-root error rather than the depth guard.
- `raster_logs_guard_after_20260915.xml`: 2 failed, 46 passed. A header-only
  positive fixture was correctly rejected by the unchanged evidence guard.
- `raster_logs_guard_after_fixture_20260915.xml`: 49/49 passed after making
  the positive fixture explicitly nonempty and adding an independent empty-
  authority rejection. Fixture rows are declared test inputs, not PHY proof.
- `raster_logs_related_guards_20260915.xml`: 160/160 passed across the raster
  publisher, CSV semantics, visual audit and live CSV plot-publication tests.

Exact broader command:

```powershell
& 'C:/ProgramData/anaconda3/python.exe' -m pytest -q tests/test_regenerate_lls_rasters_from_csv.py tests/test_lls_csv_semantics.py tests/test_audit_lls_visual_artifacts.py tests/test_live_csv_plot_publication.py --junitxml=logs/raster_logs_related_guards_20260915.xml
```

Required MATLAB testAll, export/E2E guards and final artifact verification on
the consolidated revision remain pending. Do not advance a live checkout's
source to apply this repair. Preserve original run/source identity if later
re-finalizing completed persisted evidence with a newer report implementation.

## Other report issue found, not fixed in this checkpoint

`recoverLLSRunArtifacts.localJoinStatusNotes` appends a note to an already
joined string without splitting its existing ` | ` segments. The retained
failed manifest repeats the same note five times. The status reducer must be
made idempotent and tested across repeated calls; otherwise status CSV bytes
can keep changing through a purported fixed point. This is separate from the
confirmed trusted-root rejection above and must not be hidden by extra passes.
