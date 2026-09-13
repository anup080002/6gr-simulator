# SINR limit plotting candidate — not yet integrated

Current follow-up: [main integration status](main_integration_status_20260913.md).
The candidate is now applied on main and its 37 tests pass in the integrated
268-test Python batch. This page retains the original isolated review history.

## Implementation and isolation

`pending_sinr_limit_plot_provenance.patch` contains the candidate changes to
the two plotting modules and 37 new Python test cases. `git apply --check`
passes against development revision `96f17fb9`. **The patch is unapplied.**
The three active MATLAB checkouts retain their original source files.

Development and Python tests used only two copied modules in
`%TEMP%/sixgr_sinr_plot_candidate_20260913/apps`, loaded ahead of the unchanged
repository dependencies. No extra Git worktree or MATLAB process was created.
The loaded module paths were inspected before testing. MATLAB/full-campaign
qualification of this candidate remains pending until integration is safe.

The candidate:

- centralizes selection of a receiver SINR coordinate and its provenance;
- retains the selected field's status, reason, value role and measurement
  domain, plus its raw equalizer diagnostic when that field is exported;
- labels the existing `OK_dynamic_range_limited` status explicitly in the
  chart CSV, axis, summary and legend;
- puts `[limited]` first in legends so the qualification cannot be truncated;
- preserves mixed normal/limited observations as separate plotted series;
- does not substitute raw estimates, configured SNR, geometry-only values or
  EVM-derived estimates for the chosen scheduling-input coordinate;
- rejects declared proxy/synthetic/fallback/invalid/unavailable/unverified
  SINR evidence without rescuing a finite rejected preferred field through a
  numeric alias;
- leaves missing legacy metadata blank and does not invent a raw estimate
  or transfer stale metadata from an unselected field;
- increments the materializer cache version so old derived output is not
  mistaken for output from this changed producer after integration.

## Verification

The two new tests against the real retained capture fail on the original
modules: throughput CSV lacks `sinr_value_reason`; BLER CSV lacks
`x_value_status`. With the candidate, **153 tests pass**: 37 new tests plus
116 existing radio-plot and EVM-profile tests. The final run took 11.02 s.

The initial candidate test run detected truncated limit labels; implementation
was corrected without weakening the assertions. An existing test also caught
an unintended change from the specific proxy-source rejection reason to a
generic missing-value reason; the original specific distinction was restored.

The final test command, run from the development repository root, was:

```powershell
python -c 'import sys,pytest; sys.path[:0]=["C:/Users/anup0/AppData/Local/Temp/sixgr_sinr_plot_candidate_20260913/apps","apps"]; import lls_contract_materializer, lls_radio_measurement_plots; raise SystemExit(pytest.main(["C:/Users/anup0/AppData/Local/Temp/sixgr_sinr_plot_candidate_20260913/tests/test_lls_sinr_limit_provenance.py","tests/test_lls_radio_measurement_plots.py","tests/test_lls_evm_profiles.py","-q"]))'
```

`evidence_20260913/sinr_limit_candidate_review_01` contains re-rendered CSVs
and PNGs for throughput versus SINR and PUSCH block error versus SINR. Both
PNGs were visually inspected. The limit notice is visible in the evidence
summary and axis, and survives legend truncation. The coordinate remains
45 dB; the CSV retains the raw equalizer estimate 60.0822250935111 dB and
the original limiting reason. No PHY result or original snapshot was changed.

The receipt hashes the actual isolated producer files, not the unchanged
repository modules, and explicitly records `integrated_into_runtime=false`
and `full_run_qualification=false`. The input capture hash is
`a7caa5f7d2a87f8dabb1b46bd5750c9c8619114fbe52f41e2aca23095c39317e`.
The preview script is retained beside the receipt for reproducibility; its
original execution layout is the isolated directory described above.

## Integration and broader goal remain open

Apply only after the affected checkout is no longer used by a live test job.
Then rerun the focused Python tests, MATLAB export/grant guards, both E2E
checks, and `testAll` on the integrated revision. Old-revision results do not
qualify this candidate. The patch and previews are not completion of the
production simulator, full output audit, or long impairment-enabled campaigns.

The result-integrity skill guided retaining source semantics and showing
limited estimates as limited values rather than replacing or relabeling them.
