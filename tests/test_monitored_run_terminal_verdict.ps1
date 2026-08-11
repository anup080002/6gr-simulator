$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
. (Join-Path $repoRoot "scripts\lib\monitored_run_verdict.ps1")

$fixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("sixgr_monitor_verdict_" + [guid]::NewGuid().ToString("N"))
$summaryDir = Join-Path $fixtureRoot "reports\csv"
$logPath = Join-Path $fixtureRoot "matlab.log"
New-Item -ItemType Directory -Force -Path $summaryDir | Out-Null

try {
    @"
CodexMonitoredOk=1
CodexMonitoredResultOk=1
CodexMonitoredRunCompletion=completed
CodexMonitoredRequiredFailureCount=0
"@ | Set-Content -LiteralPath $logPath -Encoding UTF8
    [pscustomobject]@{
        ResultOk = 1
        RunCompletion = "completed"
        RequiredFailureCount = 0
    } | Export-Csv -LiteralPath (Join-Path $summaryDir "scenario_summary.csv") -NoTypeInformation

    $passed = Get-SixGRMonitoredTerminalVerdict -MatlabLog $logPath -RunFolder $fixtureRoot
    if (-not $passed.Ok) {
        throw "Exact terminal success evidence was rejected: $($passed.FailureReasons)"
    }

    (Get-Content -LiteralPath $logPath -Raw).Replace("CodexMonitoredOk=1", "CodexMonitoredOk=0") |
        Set-Content -LiteralPath $logPath -Encoding UTF8
    $badMarker = Get-SixGRMonitoredTerminalVerdict -MatlabLog $logPath -RunFolder $fixtureRoot
    if ($badMarker.Ok) {
        throw "A failed MATLAB terminal marker was accepted."
    }

    (Get-Content -LiteralPath $logPath -Raw).Replace("CodexMonitoredOk=0", "CodexMonitoredOk=1") |
        Set-Content -LiteralPath $logPath -Encoding UTF8
    [pscustomobject]@{
        ResultOk = 0
        RunCompletion = "completed_with_failures"
        RequiredFailureCount = 1
    } | Export-Csv -LiteralPath (Join-Path $summaryDir "scenario_summary.csv") -NoTypeInformation
    $badSummary = Get-SixGRMonitoredTerminalVerdict -MatlabLog $logPath -RunFolder $fixtureRoot
    if ($badSummary.Ok) {
        throw "A failed canonical scenario summary was accepted."
    }

    Write-Host "PASS test_monitored_run_terminal_verdict: terminal status is fail-closed and tolerates only unavailable process exit codes."
} finally {
    if (Test-Path -LiteralPath $fixtureRoot) {
        Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
    }
}
