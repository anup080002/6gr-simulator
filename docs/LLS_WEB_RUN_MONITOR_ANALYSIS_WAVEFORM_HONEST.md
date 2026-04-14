# LLS Web Run Monitor Analysis Waveform Honest

The authenticated browser launch path is:

`/login` -> `/home` -> `/run` -> runtime YAML snapshot -> `run_6g_phy_lls_single` -> MATLAB `system_level_lls` runner -> MySQL `sim_runs`, `sim_artifacts`, `sim_run_logs` -> `/result`, `/analytics`, `/outputs`

Monitor helpers:
```powershell
.\scripts\monitor_lls_run.ps1 -BaseUrl http://127.0.0.1:62906 -RunId <run_id>
python .\scripts\validate_lls_run_outputs.py --base-url http://127.0.0.1:62906 --run-id <run_id> --strict
```

Truth rules for this browser path:
- no placeholder artifacts in strict mode
- no smoke/demo artifacts promoted into the active run
- no configured SNR relabeled as measured SINR
- unsupported outputs remain visible with exact reasons
