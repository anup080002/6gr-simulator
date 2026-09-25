param(
    [string]$Config = 'simulator/configs/scenarios/lls_7ghz_400mhz_rank2_1024qam_vxg_vsa.yaml',
    [string]$OutputDirectory = 'results',
    [string]$RunTag = ('vxg_vsa_' + (Get-Date -Format 'yyyyMMdd_HHmmss')),
    [string]$MatlabExe = 'C:\Program Files\MATLAB\R2026a\bin\matlab.exe'
)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
Push-Location -LiteralPath $repoRoot
try {
    if ($RunTag -notmatch '^[A-Za-z0-9_-]+$') { throw 'Use a simple run tag.' }
    if (-not (Test-Path -LiteralPath $MatlabExe -PathType Leaf)) { throw "MATLAB not found: $MatlabExe" }
    # Fail before the long PHY execution when local packaging/browser dependencies
    # are absent. Never install software or download a browser without a request.
    & python -c "import numpy, scipy, pandas, matplotlib; from pathlib import Path; from playwright.sync_api import sync_playwright; p=sync_playwright().start(); assert Path(p.chromium.executable_path).is_file(), 'Playwright Chromium is not installed'; p.stop()"
    if ($LASTEXITCODE -ne 0) { throw 'Python packaging dependencies or Playwright Chromium are missing; see the runbook.' }
    if (-not (Test-Path -LiteralPath 'logs' -PathType Container)) { New-Item -ItemType Directory -Path 'logs' | Out-Null }
    $launcherLog = Join-Path 'logs' ($RunTag + '.log')
    $configArgument = $Config.Replace("'", "''")
    $outputArgument = $OutputDirectory.Replace("'", "''")
    $matlabCode = "setup6GRSimToolkit('Verbose',false); out=run_6g_phy_lls_single('$configArgument','$outputArgument','$RunTag'); disp(out); assert(out.PHYCompleted,'PHY campaign incomplete');"
    & $MatlabExe -logfile $launcherLog -batch $matlabCode
    if ($LASTEXITCODE -ne 0) { throw 'MATLAB failed; retained evidence was not packaged as complete.' }
    # Resolve the actual run location from the completed manifest, not a guessed
    # output group or the most recently modified results directory.
    $manifests = @(Get-ChildItem -LiteralPath (Join-Path $OutputDirectory 'vxg_vsa') -Filter 'manifest.json' -Recurse -File |
        Where-Object { $_.Directory.Name -eq 'meta' -and $_.Directory.Parent.Name -eq $RunTag })
    if ($manifests.Count -ne 1) { throw 'Cannot uniquely resolve this completed run.' }
    $runFolder = $manifests[0].Directory.Parent.FullName
    Copy-Item -LiteralPath $launcherLog -Destination (Join-Path $runFolder 'meta/console_log.log')
    & python 'apps/build_lab_waveform_package.py' $runFolder 2>&1 | Tee-Object -FilePath (Join-Path 'logs' ($RunTag + '_package.log'))
    if ($LASTEXITCODE -ne 0) { throw 'Waveform packaging failed; do not hand off files.' }
    & python 'tests/check_lab_waveform_browser.py' $runFolder 2>&1 | Tee-Object -FilePath (Join-Path 'logs' ($RunTag + '_browser.log'))
    if ($LASTEXITCODE -ne 0) { throw 'Browser acceptance failed; waveform evidence is retained.' }
    & python 'apps/seal_lab_waveform_package.py' $runFolder
    if ($LASTEXITCODE -ne 0) { throw 'Final artifact sealing failed.' }
    Write-Host "RUN_FOLDER=$runFolder"
    Write-Host "Open: $runFolder\webgui\index.html"
    Write-Host 'Physical instrument capability remains UNKNOWN. No RF was enabled.'
} finally {
    Pop-Location
}
