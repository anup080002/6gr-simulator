# Shareable validation logs

From Windows Terminal (PowerShell), at the repository root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run_server_testall.ps1
```

Select another installed MATLAB explicitly:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run_server_testall.ps1 -MatlabExe "C:\Program Files\MATLAB\R2025b\bin\matlab.exe"
```

Each invocation creates a unique `logs/testall_<UTC>_<id>/` directory and a
ZIP beside it. Share the ZIP, including `matlab.log`, `launcher.json`,
`environment.json`, `summary.json`, `test_report.json`, `tests.csv` and
`failures.csv`. Startup errors or crashes can leave only partial files;
these are failures/incomplete runs, never a PASS. If interrupted, share the
folder directly. No log is overwritten or automatically deleted.

`-PreflightOnly` checks setup and inventories dependencies without running
tests. It is not a testAll pass. `-Tests testConfig,testLLS_DL` can be used in
a PowerShell invocation (`& .\scripts\run_server_testall.ps1 -Tests ...`) to
rerun named tests; that is only a focused pass. The default runs **all** tests.

Generated logs remain local and Git-ignored, so running tests does not dirty
the checkout or accidentally publish local paths. Review bundles before
sharing: diagnostics contain local installation/repository paths. They do not
intentionally collect credentials or the full environment-variable set.

Keep this checkout unchanged while a test is running. Update it only after
the process finishes. Do not interpret testAll success as 12 dB scenario or
all-MATLAB-version qualification. See [server instructions](../docs/lls/server_testall_handoff_20260913.md).
