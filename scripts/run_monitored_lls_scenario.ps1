param(
    [string]$ScenarioPath = "simulator/configs/scenarios/lls_mobile_2ue_100kmh_1sector_full_capture.yaml",
    [string]$OutputDir = "results",
    [string]$RunTag = "",
    [int]$PollSeconds = 10,
    [int]$TailLines = 10,
    [string]$MatlabExe = ""
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "lib\monitored_run_verdict.ps1")

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
if ([string]::IsNullOrWhiteSpace($MatlabExe)) {
    $MatlabExe = if ([string]::IsNullOrWhiteSpace($env:SIXGR_MATLAB_EXE)) {
        "C:\Program Files\MATLAB\R2024a\bin\matlab.exe"
    } else {
        $env:SIXGR_MATLAB_EXE
    }
}
if (!(Test-Path -LiteralPath $MatlabExe)) {
    throw "MATLAB executable not found: $MatlabExe"
}

function Resolve-AbsolutePath {
    param(
        [string]$PathText,
        [string]$BasePath
    )
    if ([string]::IsNullOrWhiteSpace($PathText)) {
        return ""
    }
    if ([System.IO.Path]::IsPathRooted($PathText)) {
        return [System.IO.Path]::GetFullPath($PathText)
    }
    return [System.IO.Path]::GetFullPath((Join-Path $BasePath $PathText))
}

function Resolve-ScenarioId {
    param([string]$ScenarioFile)
    $raw = Get-Content -LiteralPath $ScenarioFile -Raw
    $m = [regex]::Match($raw, '(?m)^\s*scenario_id\s*:\s*["'']?([^"''#\r\n]+)')
    if ($m.Success) {
        return $m.Groups[1].Value.Trim()
    }
    $m = [regex]::Match($raw, '(?m)^\s*name\s*:\s*["'']?([^"''#\r\n]+)')
    if ($m.Success) {
        return $m.Groups[1].Value.Trim()
    }
    throw "Could not resolve scenario_id or scenario.name from $ScenarioFile"
}

function Get-LogicalRunFolder {
    param(
        [string]$ResolvedOutputDir,
        [string]$ScenarioId,
        [string]$Leaf
    )
    return [System.IO.Path]::GetFullPath((Join-Path $ResolvedOutputDir (Join-Path "lls" (Join-Path $ScenarioId $Leaf))))
}

function Read-JsonFile {
    param([string]$PathText)
    if (!(Test-Path -LiteralPath $PathText)) {
        return $null
    }
    try {
        return (Get-Content -LiteralPath $PathText -Raw | ConvertFrom-Json)
    } catch {
        return $null
    }
}

function Get-LastCsvRow {
    param([string]$PathText)
    if (!(Test-Path -LiteralPath $PathText)) {
        return $null
    }
    try {
        $rows = Import-Csv -LiteralPath $PathText
        if ($null -eq $rows -or $rows.Count -lt 1) {
            return $null
        }
        return $rows[-1]
    } catch {
        return $null
    }
}

function Get-FileSummary {
    param([string]$PathText)
    if (!(Test-Path -LiteralPath $PathText)) {
        return $null
    }
    $item = Get-Item -LiteralPath $PathText
    [pscustomobject]@{
        FullName = $item.FullName
        Length = [int64]$item.Length
        LastWriteTimeUtc = $item.LastWriteTimeUtc.ToString("o")
    }
}

function Show-StatusSnapshot {
    param([string]$RunFolder)
    $statusPath = Join-Path $RunFolder "RUNNING.status.json"
    $status = Read-JsonFile -PathText $statusPath
    if ($null -eq $status) {
        Write-Host "STATUS waiting_for_runtime_status path=$statusPath"
        return
    }
    Write-Host ("STATUS stage={0} slot={1}/{2} completed={3} result_ok={4} issues={5} critical={6} pid={7}" -f `
        $status.CurrentStage, $status.CurrentSlot, $status.TotalSlots, `
        $status.RunCompleted, $status.ResultOk, $status.LatestIssueCount, `
        $status.LatestCriticalIssueCount, $status.MatlabPID)
}

function Show-StageProgressSnapshot {
    param([string]$RunFolder)
    $path = Join-Path $RunFolder "reports\csv\live_stage_progress.csv"
    $row = Get-LastCsvRow -PathText $path
    if ($null -eq $row) {
        Write-Host "STAGE waiting_for_live_stage_progress"
        return
    }
    Write-Host ("STAGE idx={0} name={1} status={2} slot_start={3} slot_end={4} elapsed_s={5} artifacts={6} csv_rows={7} issues={8} critical={9}" -f `
        $row.StageIndex, $row.StageName, $row.Status, $row.CurrentSlotStart, `
        $row.CurrentSlotEnd, $row.ElapsedSeconds, $row.ArtifactsCreated, `
        $row.CsvRowsCreated, $row.IssuesCreated, $row.CriticalIssuesCreated)
}

function Show-ArtifactSummary {
    param(
        [string]$Label,
        [string]$PathText
    )
    $summary = Get-FileSummary -PathText $PathText
    if ($null -eq $summary) {
        return
    }
    Write-Host ("ARTIFACT {0} bytes={1} updated_utc={2} path={3}" -f `
        $Label, $summary.Length, $summary.LastWriteTimeUtc, $summary.FullName)
}

function Show-LogTail {
    param(
        [string]$Label,
        [string]$PathText,
        [int]$Lines
    )
    if (!(Test-Path -LiteralPath $PathText)) {
        return
    }
    Write-Host ("LOG {0} path={1}" -f $Label, $PathText)
    try {
        Get-Content -LiteralPath $PathText -Tail $Lines | ForEach-Object {
            Write-Host ("  {0}" -f $_)
        }
    } catch {
        Write-Host ("  unable_to_tail_log: {0}" -f $_.Exception.Message)
    }
}

function Show-DashboardSnapshot {
    param([string]$ActiveRunTag)
    $monitorScript = Join-Path $PSScriptRoot "monitor_lls_run.ps1"
    if (!(Test-Path -LiteralPath $monitorScript)) {
        return
    }
    try {
        & $monitorScript -RunTag $ActiveRunTag -Once -Quiet
    } catch {
        Write-Host ("DASHBOARD unavailable run_tag={0} reason={1}" -f $ActiveRunTag, $_.Exception.Message)
    }
}

$ScenarioAbs = Resolve-AbsolutePath -PathText $ScenarioPath -BasePath $RepoRoot
if (!(Test-Path -LiteralPath $ScenarioAbs)) {
    throw "Scenario file not found: $ScenarioAbs"
}
$ScenarioId = Resolve-ScenarioId -ScenarioFile $ScenarioAbs
if ([string]::IsNullOrWhiteSpace($RunTag)) {
    $RunTag = "$ScenarioId" + "_" + (Get-Date -Format "yyyyMMdd_HHmmss")
}
$ResolvedOutputDir = Resolve-AbsolutePath -PathText $OutputDir -BasePath $RepoRoot
$LogicalRunFolder = Get-LogicalRunFolder -ResolvedOutputDir $ResolvedOutputDir -ScenarioId $ScenarioId -Leaf $RunTag

$LogDir = Join-Path $RepoRoot "logs\monitored_lls_runs"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$MatlabLog = Join-Path $LogDir "$RunTag.log"
$MatlabErr = Join-Path $LogDir "$RunTag.err"
$DriverPath = Join-Path $LogDir "$RunTag.m"

$driverText = @"
cd('$($RepoRoot.Replace("'", "''"))');
addpath(pwd,'-begin');
rehash;
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
out = run_6g_phy_lls_single('$($ScenarioAbs.Replace("'", "''"))','$($ResolvedOutputDir.Replace("'", "''"))','$($RunTag.Replace("'", "''"))');
fprintf('CodexMonitoredRunFolder=%s\n', char(string(out.RunFolder)));
fprintf('CodexMonitoredOk=%d\n', double(logical(out.Ok)));
if isfield(out,'Manifest')
    try
        fprintf('CodexMonitoredResultOk=%d\n', double(logical(out.Manifest.ResultOk)));
        fprintf('CodexMonitoredRunCompletion=%s\n', char(string(out.Manifest.RunCompletion)));
        fprintf('CodexMonitoredRequiredFailureCount=%g\n', double(out.Manifest.RequiredFailureCount));
    catch
    end
end
"@
Set-Content -LiteralPath $DriverPath -Value $driverText -Encoding UTF8

Write-Host "Monitoring real LLS flow from one repo only."
Write-Host "RepoRoot: $RepoRoot"
Write-Host "Scenario: $ScenarioAbs"
Write-Host "ScenarioID: $ScenarioId"
Write-Host "RunTag: $RunTag"
Write-Host "LogicalRunFolder: $LogicalRunFolder"
Write-Host "MATLAB log: $MatlabLog"

$batchCommand = "run('$($DriverPath.Replace("'", "''"))')"
$argumentText = '-batch "' + $batchCommand.Replace('"', '\"') + '"'
$proc = Start-Process -FilePath $MatlabExe -ArgumentList $argumentText -WorkingDirectory $RepoRoot -RedirectStandardOutput $MatlabLog -RedirectStandardError $MatlabErr -PassThru -WindowStyle Hidden

do {
    Write-Host ("[{0}] MONITOR run_tag={1} pid={2}" -f (Get-Date -Format o), $RunTag, $proc.Id)
    Show-DashboardSnapshot -ActiveRunTag $RunTag
    Show-StatusSnapshot -RunFolder $LogicalRunFolder
    Show-StageProgressSnapshot -RunFolder $LogicalRunFolder

    Show-ArtifactSummary -Label "runtime_issue_trace" -PathText (Join-Path $LogicalRunFolder "reports\csv\runtime_issue_trace.csv")
    Show-ArtifactSummary -Label "runtime_artifact_generation_trace" -PathText (Join-Path $LogicalRunFolder "reports\csv\runtime_artifact_generation_trace.csv")
    Show-ArtifactSummary -Label "live_dl_scheduler_grants" -PathText (Join-Path $LogicalRunFolder "packet_flow\csv\live_dl_scheduler_grants.csv")
    Show-ArtifactSummary -Label "live_ul_scheduler_grants" -PathText (Join-Path $LogicalRunFolder "packet_flow\csv\live_ul_scheduler_grants.csv")
    Show-ArtifactSummary -Label "slot_trace_reports" -PathText (Join-Path $LogicalRunFolder "reports\csv\slot_trace.csv")
    Show-ArtifactSummary -Label "slot_trace_packet_flow" -PathText (Join-Path $LogicalRunFolder "packet_flow\csv\slot_trace.csv")
    Show-ArtifactSummary -Label "live_tx_rx_stage_trace" -PathText (Join-Path $LogicalRunFolder "reports\csv\live_tx_rx_stage_trace.csv")
    Show-ArtifactSummary -Label "live_channel_estimation_tti" -PathText (Join-Path $LogicalRunFolder "reports\csv\live_channel_estimation_tti.csv")
    Show-ArtifactSummary -Label "live_channel_state_tti" -PathText (Join-Path $LogicalRunFolder "reports\csv\live_channel_state_tti.csv")
    Show-ArtifactSummary -Label "live_modulation_demodulation_trace" -PathText (Join-Path $LogicalRunFolder "reports\csv\live_modulation_demodulation_trace.csv")
    Show-ArtifactSummary -Label "live_waveform_preview" -PathText (Join-Path $LogicalRunFolder "reports\csv\live_waveform_preview.csv")

    Show-LogTail -Label "matlab_stdout" -PathText $MatlabLog -Lines $TailLines
    Show-LogTail -Label "matlab_stderr" -PathText $MatlabErr -Lines $TailLines

    if ($proc.HasExited) {
        break
    }
    Start-Sleep -Seconds ([Math]::Max(1, $PollSeconds))
} while ($true)

$proc.WaitForExit()
$proc.Refresh()
$rawExitCode = $null
try {
    $rawExitCode = $proc.ExitCode
} catch {
    $rawExitCode = $null
}
$exitCodeAvailable = $null -ne $rawExitCode -and `
    -not [string]::IsNullOrWhiteSpace([string]$rawExitCode)
$exitCodeText = if ($exitCodeAvailable) { [string]$rawExitCode } else { "unavailable" }
Write-Host ("[{0}] MATLAB exited code={1}" -f (Get-Date -Format o), $exitCodeText)
Show-DashboardSnapshot -ActiveRunTag $RunTag
Show-StatusSnapshot -RunFolder $LogicalRunFolder
Show-StageProgressSnapshot -RunFolder $LogicalRunFolder
Show-LogTail -Label "matlab_stdout" -PathText $MatlabLog -Lines $TailLines
Show-LogTail -Label "matlab_stderr" -PathText $MatlabErr -Lines $TailLines

$terminalVerdict = Get-SixGRMonitoredTerminalVerdict -MatlabLog $MatlabLog -RunFolder $LogicalRunFolder
Write-Host ("TERMINAL result_ok={0} completion={1} required_failures={2} markers_ok={3} reasons={4}" -f `
    $terminalVerdict.SummaryResultOk, $terminalVerdict.SummaryRunCompletion, `
    $terminalVerdict.SummaryRequiredFailureCount, $terminalVerdict.MarkerOk, `
    $terminalVerdict.FailureReasons)

$processFailed = $exitCodeAvailable -and [int]$rawExitCode -ne 0
if ($processFailed -or -not $terminalVerdict.Ok) {
    throw "Monitored LLS run failed (process_exit=$exitCodeText terminal_ok=$($terminalVerdict.Ok) reasons=$($terminalVerdict.FailureReasons)). Inspect $MatlabLog, $MatlabErr, and $LogicalRunFolder"
}
if (-not $exitCodeAvailable) {
    Write-Warning "MATLAB process exit code was unavailable; accepting only because independent terminal log markers and scenario_summary.csv both report completed success with zero required failures."
}
