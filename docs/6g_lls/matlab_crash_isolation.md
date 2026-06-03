# MATLAB Crash Isolation Ladder

Use full executable paths for every probe. Do not rely on `matlab` from `PATH`.

## Known executables

```powershell
"C:\Program Files\MATLAB\R2023b\bin\matlab.exe"
"C:\Program Files\MATLAB\R2025b\bin\matlab.exe"
```

## Recommended order

1. Test `R2023b` first because it is currently the only version proven to pass bare batch startup.
2. Keep `R2025b` isolated until its batch crash is understood.
3. Do not add the repo to MATLAB path until Gates 1 and 2 pass for a given version.

## Gate 1: bare MATLAB health

```powershell
"C:\Program Files\MATLAB\R2023b\bin\matlab.exe" -batch "disp('ok')"
"C:\Program Files\MATLAB\R2023b\bin\matlab.exe" -batch "version"

"C:\Program Files\MATLAB\R2025b\bin\matlab.exe" -batch "disp('ok')"
"C:\Program Files\MATLAB\R2025b\bin\matlab.exe" -batch "version"
```

Expected result:
- `ok` prints and `version` returns normally.

Interpretation:
- pass: MATLAB binary is healthy enough for batch mode
- fail: treat as installation/runtime problem, not a repo problem

## Gate 2: clean path and clean preferences

```powershell
"C:\Program Files\MATLAB\R2023b\bin\matlab.exe" -batch "restoredefaultpath; rehash toolboxcache; disp('minimal_path_ok')"

$env:MATLAB_PREFDIR="C:\Temp\matlab_pref_r2023b_clean"
"C:\Program Files\MATLAB\R2023b\bin\matlab.exe" -batch "disp('ok_cleanprefs')"

$env:MATLAB_PREFDIR="C:\Temp\matlab_pref_r2025b_clean"
"C:\Program Files\MATLAB\R2025b\bin\matlab.exe" -batch "disp('ok_cleanprefs')"
```

Expected result:
- clean-path probe succeeds
- clean-prefs probe succeeds

Interpretation:
- default prefs fail but clean prefs pass: preference/cache corruption
- both fail: not just preferences

## Gate 3: safe repo bring-up

Use root-only repo setup first. This avoids `genpath`-style broad path expansion and keeps `codegen/` off path.

```powershell
$repo="C:/Anup/6gsimulation/sixgr_foundation_v3"
"C:\Program Files\MATLAB\R2023b\bin\matlab.exe" -batch "restoredefaultpath; rehash toolboxcache; addpath('$repo'); addpath(fullfile('$repo','tests')); setup6GRSimToolkit('Verbose',false,'AddSubfolders',false,'RunToolboxChecks',false); disp('setup_ok')"
```

Expected result:
- `setup_ok`

Interpretation:
- pass: repo root and package loading are not crashing MATLAB
- fail: repo path or setup code is implicated

## Gate 4: minimal smoke execution

```powershell
$repo="C:/Anup/6gsimulation/sixgr_foundation_v3"
"C:\Program Files\MATLAB\R2023b\bin\matlab.exe" -batch "restoredefaultpath; rehash toolboxcache; addpath('$repo'); addpath(fullfile('$repo','tests')); setup6GRSimToolkit('Verbose',false,'AddSubfolders',false,'RunToolboxChecks',false); testLLSPatchSmoke"
```

Expected result:
- smoke test runs and returns exit code `0`

Interpretation:
- pass: environment is stable enough to start runtime validation
- fail with MATLAB access violation: still an environment problem
- fail with MATLAB assertion/runtime error: environment is healthy enough, next blocker is repo logic or release compatibility

## Diagnostic side probes

Use these only to help classify the crash:

```powershell
"C:\Program Files\MATLAB\R2025b\bin\matlab.exe" -nojvm -batch "disp('ok_nojvm')"
"C:\Program Files\MATLAB\R2025b\bin\matlab.exe" -nodesktop -nosplash -batch "disp('ok_nodesktop')"
```

If these still crash, the issue is not just graphics desktop startup.

## Native-binary isolation

The repo contains many native binaries, including root-level `.mexw64` files and `codegen\mex\...` outputs. To minimize exposure:

1. Do not call `setup6GRSimToolkit` with `AddSubfolders=true` during early isolation.
2. Use only:

```powershell
addpath('C:/Anup/6gsimulation/sixgr_foundation_v3')
addpath(fullfile('C:/Anup/6gsimulation/sixgr_foundation_v3','tests'))
setup6GRSimToolkit('Verbose',false,'AddSubfolders',false,'RunToolboxChecks',false)
```

3. If Gate 3 starts failing only after repo path is added, temporarily quarantine root-level `.mexw64` files and keep `codegen/` off path before retrying.

## Automated run

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\matlab_crash_isolation.ps1
```

This writes timestamped logs and a Markdown summary under `results/_matlab_crash_isolation/`.
