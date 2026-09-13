# Windows server testAll handoff

This is a development validation handoff, **not** a successful 12 dB release.
Shared feedback/combined UCI and the full measurement closure remain open.
The subsequent [HARQ ownership repair](harq_feedback_disposition_20260913.md)
adds stale-feedback and duplicate-callback guards. Ten focused tests passed
on that repair; full testAll and cross-MATLAB-version compatibility are still
to be established on the selected checkout revision.
The same-chain sweep already includes `[-30,-20,-10,0,10,12,20,30,40]`.
Do not start that sweep until the local 12 dB scenario and its measurement
audit are qualified; testAll alone is not that qualification.

## Fresh server checkout

Install Git with Git LFS, a licensed MATLAB installation and the required
toolboxes. Clone the repository instead of downloading GitHub's source ZIP:
retained MAT test evidence is stored in Git LFS.

```powershell
git lfs install
git clone https://github.com/anup080002/6gr-simulator.git
cd 6gr-simulator
git lfs pull
git lfs fsck
git status --short
```

Do not proceed after a failed LFS download/check. A MAT pointer is not a
waveform fixture. Missing objects must be reported, not replaced with fake
data. No force-pull, reset or deletion is needed to run tests.

The existing Python requirements are `requirements-initial-access.txt` and
`apps/requirements-webgui.txt`. Use an environment with the required packages
and ensure its Python is discoverable before starting MATLAB. The setup
diagnostic reports the selected Python/PyYAML backend. This launcher does not
install software or change your licenses automatically.

## Run from Windows Terminal / PowerShell

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run_server_testall.ps1 -PreflightOnly
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run_server_testall.ps1
```

Use `-MatlabExe "C:\Program Files\MATLAB\R2025b\bin\matlab.exe"` (or your
actual release/path) on either command if MATLAB is not on PATH or several
versions are installed. The current local reference is R2026a. Older/newer
releases are **not certified** by selecting them: the launcher records the
actual release/toolboxes, runs the same assertions, and preserves failures.
No tests are silently skipped because of version differences.

The launcher uses MATLAB's documented `-batch`, `-wait` and `-logfile`
options, checks the process exit code and terminal report, and saves a ZIP
under repository-local `logs/`. [MathWorks Windows command-line reference](https://www.mathworks.com/help/matlab/ref/matlabwindows.html).
For embedded Python, match the installed MATLAB release to MathWorks'
[Python compatibility table](https://www.mathworks.com/support/requirements/python-compatibility.html).

Share the entire log ZIP after a run, even on failure. While it runs, the last
`FULLSTACK_TEST_START` without a matching end identifies the active test; it
does not mean that test failed. A killed or crashed run remains incomplete.
Large simulation outputs outside `/logs` remain where each test writes them;
the compact bundle contains diagnostic reports, not every generated IQ array.

## Updating later

After all MATLAB jobs in that checkout have exited:

```powershell
git status --short
git pull --ff-only
git lfs pull
git lfs fsck
```

Preserve any local edits first. A later push after successful local 12 dB
validation must include the exact source revision and that run's own
measurement/CSV/PNG/IQ verdict. Until then, do not label this handoff or the
sweep as passed.
