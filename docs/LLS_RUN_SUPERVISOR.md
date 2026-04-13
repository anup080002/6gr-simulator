# LLS Run Supervisor

The local supervisor for the locked 4 GHz / 100 MHz LLS scenario is:

```text
scripts/run_lls_3gpp_4ghz_100mhz_longrun.ps1
```

It is intentionally conservative:

- pins MATLAB to `C:\Program Files\MATLAB\R2023b\bin\matlab.exe`
- calls the real MATLAB scenario entrypoint `run_6g_phy_lls_single`
- keeps run outputs and logs additive
- does not delete previous DB rows, CSVs, artifacts, or browser pages
- polls `http://127.0.0.1:62906/api/run/<run_id>/live` while a run is active
- validates the browser/API surface through `scripts/validate_lls_run_outputs.py`
- reruns with the same seeds for deterministic replay after a successful attempt

## Commands

Validate the scenario config through MATLAB R2023b:

```powershell
& "C:\Program Files\MATLAB\R2023b\bin\matlab.exe" -batch "cd('c:\Anup\6gsimulation\sixgr_foundation_v2 (2)'); setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false); scfg=sixgr.lls6g.config.loadScenarioConfig('simulator/configs/scenarios/lls_3gpp_4ghz_100mhz_longrun.yaml'); cfg=sixgr.lls6g.buildInternalConfig(scfg,'results'); assert(cfg.run.numTTI==50000); assert(cfg.run.totalTime_ms==25000);"
```

Launch the long-run supervisor:

```powershell
.\scripts\run_lls_3gpp_4ghz_100mhz_longrun.ps1 -MaxAttempts 10
```

Monitor the latest browser-backed run once:

```powershell
.\scripts\monitor_lls_run.ps1 -Latest -Once
```

Validate a finished run through the browser API:

```powershell
python .\scripts\validate_lls_run_outputs.py --base-url http://127.0.0.1:62906 --run-id <run_id> --strict
```

## Attempt Report

Every supervisor attempt writes:

- stdout: `logs/lls_3gpp_4ghz_100mhz_longrun/<run_tag>.log`
- stderr: `logs/lls_3gpp_4ghz_100mhz_longrun/<run_tag>.log.err`

On failure, preserve the logs and inspect the final error, truth-contract artifacts, and browser live payload. Patch the real root cause, then rerun the same supervisor command.
