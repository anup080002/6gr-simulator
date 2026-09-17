# Rate-matrix checkpoint: 18 focused guards passed

Source: `91046b231f28449dea7961906a01e60deb6d648e`.
MATLAB: R2026a Update 4, Windows.
Finished: 2026-09-17 09:28:50.597 UTC / 14:58:50.597 IST.
Duration: 10,523.4498498 seconds. Tests: 18. Failures: 0.

The four receipts are copied unchanged from
`logs/research_rate_matrix_91046b23_20260917/guards` and SHA256-compared
against their originals before committing. `test_report.json` gives each
test's verdict and duration; `summary.json` identifies the completed scope.

This is not a full-suite verdict. The existing job started unfiltered
`testAll` at 09:28:50.706 UTC. The checkpoint predates the selected rate-0.82
IQ YAML. Its focused list does not include `testResearchTDDLink` and cannot
override that test's newer-source CSV-import failure. It does not qualify
the failed 12 dB scenario, R2023b, detector statistics, or Keysight import.

No code, thresholds, assertions, or IQ data were changed to preserve this
receipt. The independently recorded failure remains intact.
