# MATLAB Crash Triage

Use this checklist when MATLAB exits with `0xc0000005` before the LLS tests can even start.

## Fast path

1. Run the automated triage script:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\triage_matlab_startup_crash.ps1
```

2. Inspect the generated artifacts under `results/_matlab_crash_triage/`:

- `summary.md`: probe exit codes at a glance
- `plain_batch.log`: whether MATLAB can launch at all
- `softwareopengl_batch.log`: whether graphics initialization is involved
- `minimal_path_batch.log`: whether the default path/toolbox cache is the problem
- `startup_lookup_batch.log`: whether a user `startup.m` is being picked up
- `repo_setup_only.log`: whether `setup6GRSimToolkit` triggers the crash
- `lls_patch_smoke.log`: whether the new smoke test can run once setup succeeds
- `native_binaries.txt`: repo-local MEX and native DLL inventory
- `startup_candidates.txt`: likely `startup.m` locations on disk
- `where_matlab.txt` and `get_command_matlab.txt`: executable resolution

## Manual probe sequence

Run these in order and stop at the first crash point:

```powershell
matlab -batch "disp('ok')"
matlab -softwareopengl -batch "disp('ok')"
matlab -batch "restoredefaultpath; rehash toolboxcache; disp('minimal_path_ok')"
matlab -batch "disp(which('startup','-all'))"
matlab -batch "restoredefaultpath; rehash toolboxcache; addpath('C:/Anup/6gsimulation/sixgr_foundation_v3'); setup6GRSimToolkit('Verbose',false); disp('setup_ok')"
matlab -batch "restoredefaultpath; rehash toolboxcache; addpath('C:/Anup/6gsimulation/sixgr_foundation_v3'); setup6GRSimToolkit('Verbose',false); testLLSPatchSmoke"
```

## What each failure point usually means

- `plain_batch` crashes:
  MATLAB itself, licensing, antivirus, native runtime, or a global `startup.m` issue.
- `softwareopengl_batch` works but `plain_batch` fails:
  likely graphics/OpenGL initialization.
- `minimal_path_batch` works but `repo_setup_only` fails:
  repo path setup, `startup.m`, or a repo-loaded native binary.
- `repo_setup_only` works but `lls_patch_smoke` fails:
  MATLAB is stable enough to debug the simulator itself.

## Targeted checks

- Rename or temporarily move user `startup.m` files shown in `startup_candidates.txt`.
- Clear toolbox caches with:

```powershell
matlab -batch "restoredefaultpath; rehash toolboxcache; savepath"
```

- Compare native binary inventory in `native_binaries.txt` against the files that `setup6GRSimToolkit` adds to path.
- If only repo setup crashes, temporarily comment out MEX-path additions in the setup flow and retry the same probe sequence.

## First verification command after MATLAB is stable

Run this before the full suite:

```powershell
matlab -batch "setup6GRSimToolkit('Verbose',false); testLLSPatchSmoke"
```

Then move on to:

```powershell
matlab -batch "setup6GRSimToolkit('Verbose',false); testAll"
```
