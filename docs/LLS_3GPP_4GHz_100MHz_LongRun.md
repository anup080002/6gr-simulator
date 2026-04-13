# LLS 3GPP 4 GHz 100 MHz Long Run

This is the locked default MATLAB-first LLS scenario:

- Scenario: `lls_3gpp_4ghz_100mhz_longrun`
- Active scenario file: `simulator/configs/scenarios/lls_3gpp_4ghz_100mhz_longrun.yaml`
- Compatibility alias: `configs/scenarios/lls_3gpp_4ghz_100mhz_longrun.yaml`
- Center frequency: `4 GHz`
- Bandwidth: `100 MHz`
- Duplex: `TDD`
- SCS: `30 kHz`
- PRB grid: `273 RB`
- TDD pattern: `DDDSU`
- Topology: `7` sites, `3` sectors per site, `21` cells, `100` UEs
- Intersite distance: `600 m`
- Run profile: `very_long_run`
- Slot budget: `50000` total, `5000` warmup, `45000` measurement
- Deterministic replay: enabled
- Honesty mode: `strict`
- Unsupported-output policy: `show_unavailable_with_reason`
- Backend: `mysql_web`

The active browser/backend default is `lls_3gpp_4ghz_100mhz_longrun.yaml`.

## Truth Policy

This scenario must not emit smoke data, synthetic measured outputs, placeholder chart files, or fallback rows in primary result tables. Unsupported outputs remain visible through the output coverage and honest-unavailable registries with an exact reason.

The MATLAB run path is:

```text
run_6g_phy_lls_single -> sixgr.lls6g.runners.runSingle -> MATLAB runtime -> MySQL artifacts -> browser API/pages
```

Only this MATLAB executable is valid for this scenario:

```text
C:\Program Files\MATLAB\R2023b\bin\matlab.exe
```

## Run

```powershell
.\scripts\run_lls_3gpp_4ghz_100mhz_longrun.ps1 -MaxAttempts 10
```

The script launches MATLAB R2023b, streams attempt logs under `logs/lls_3gpp_4ghz_100mhz_longrun`, polls the browser API during execution, validates the final browser/API payload, and performs a deterministic replay unless `-SkipReplay` is supplied.

## Inspect

Use these browser targets while the backend is running on port `62906`:

```text
http://127.0.0.1:62906/home
http://127.0.0.1:62906/reports
http://127.0.0.1:62906/analytics
http://127.0.0.1:62906/artifacts?run_id=1
```

If the actual run id is not `1`, use the latest id from:

```text
http://127.0.0.1:62906/api/runs?limit=1
```

## Supported Output Families

Supported outputs are determined by the runtime truth contract and the MySQL artifact manifest. The strict run expects canonical artifacts for scenario summary, resolved config, artifact inventory, truth contract summary, output coverage registry, live logs, and any implemented scheduler/MAC/PHY/channel/mobility/power tables emitted by the active runtime.

Unavailable outputs remain in the registry with `implemented_flag=false` or an unavailable status and a blocker reason. The run must not create fake chart files for these items.
