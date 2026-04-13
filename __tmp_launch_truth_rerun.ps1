$tag = 'codex_truth_rerun_20260407_03'
$cfg = 'simulator/configs/scenarios/lls_700mhz_20mhz_multiuser_macro_100ue.yaml'
$log = "C:\Anup\6gsimulation\sixgr_foundation_v2\tmp_web_runs\$tag.full.log"
$matlab = 'C:\Program Files\MATLAB\R2023b\bin\matlab.exe'
$expr = "& '$matlab' -batch ""setup6GRSimToolkit('Verbose',false); run_6g_phy_lls_single('$cfg','results','$tag');"" *> '$log'"
Start-Process -FilePath powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $expr) -WindowStyle Hidden
Write-Output $tag
Write-Output $log
