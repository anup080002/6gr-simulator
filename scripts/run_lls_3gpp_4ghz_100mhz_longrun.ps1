param(
    [string]$ScenarioPath = "simulator/configs/scenarios/lls_3gpp_4ghz_100mhz_longrun.yaml",
    [string]$OutputDir = "results",
    [string]$RunTag = "",
    [int]$MaxAttempts = 10,
    [int]$PollSeconds = 30,
    [int]$MaxWallMinutes = 0,
    [string]$BaseUrl = "",
    [switch]$SkipReplay
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$MatlabExe = if ([string]::IsNullOrWhiteSpace($env:SIXGR_MATLAB_EXE)) { "C:\Program Files\MATLAB\R2024a\bin\matlab.exe" } else { $env:SIXGR_MATLAB_EXE }

if (!(Test-Path -LiteralPath $MatlabExe)) {
    throw "Pinned MATLAB R2024a executable not found: $MatlabExe"
}

if ([string]::IsNullOrWhiteSpace($RunTag)) {
    $RunTag = "lls_3gpp_4ghz_100mhz_longrun_" + (Get-Date -Format "yyyyMMdd_HHmmss")
}

$LogDir = Join-Path $RepoRoot "logs\lls_3gpp_4ghz_100mhz_longrun"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

if ([string]::IsNullOrWhiteSpace($env:MYSQL_HOST)) { $env:MYSQL_HOST = "localhost" }
if ([string]::IsNullOrWhiteSpace($env:MYSQL_PORT)) { $env:MYSQL_PORT = "3306" }
if ([string]::IsNullOrWhiteSpace($env:MYSQL_USER)) { $env:MYSQL_USER = "root" }
if ([string]::IsNullOrWhiteSpace($env:MYSQL_PASSWORD)) { $env:MYSQL_PASSWORD = "root" }
if ([string]::IsNullOrWhiteSpace($env:MYSQL_DATABASE)) { $env:MYSQL_DATABASE = "sixgr_results" }

function Resolve-DashboardBaseUrl {
    param([string]$Candidate)
    if (-not [string]::IsNullOrWhiteSpace($Candidate)) {
        return $Candidate.TrimEnd('/')
    }
    if (-not [string]::IsNullOrWhiteSpace($env:SIXGR_DASHBOARD_BASE_URL)) {
        return $env:SIXGR_DASHBOARD_BASE_URL.TrimEnd('/')
    }
    $listenerPath = Join-Path $RepoRoot "tmp_web_runs\dashboard_listener.json"
    if (Test-Path -LiteralPath $listenerPath) {
        try {
            $listener = Get-Content -LiteralPath $listenerPath -Raw | ConvertFrom-Json
            foreach ($prop in @("local_url", "intranet_url")) {
                $value = [string]$listener.$prop
                if (-not [string]::IsNullOrWhiteSpace($value)) {
                    return $value.TrimEnd('/')
                }
            }
        } catch {
        }
    }
    return "http://127.0.0.1:62906"
}

$BaseUrl = Resolve-DashboardBaseUrl -Candidate $BaseUrl

function Invoke-LongRunAttempt {
    param(
        [string]$AttemptTag,
        [int]$AttemptIndex
    )

    $logPath = Join-Path $LogDir "$AttemptTag.log"
    $driverPath = Join-Path $LogDir "$AttemptTag.m"
    $driverText = @"
cd('$($RepoRoot.Replace("'", "''"))');
addpath(pwd,'-begin');
rehash;
setenv('MYSQL_HOST','$($env:MYSQL_HOST.Replace("'", "''"))');
setenv('MYSQL_PORT','$($env:MYSQL_PORT.Replace("'", "''"))');
setenv('MYSQL_USER','$($env:MYSQL_USER.Replace("'", "''"))');
setenv('MYSQL_PASSWORD','$($env:MYSQL_PASSWORD.Replace("'", "''"))');
setenv('MYSQL_DATABASE','$($env:MYSQL_DATABASE.Replace("'", "''"))');
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
out=run_6g_phy_lls_single('$($ScenarioPath.Replace("'", "''"))','$($OutputDir.Replace("'", "''"))','$($AttemptTag.Replace("'", "''"))');
ok=isfield(out,'Ok') && logical(out.Ok);
fprintf('CodexLongRunResultOk=%d\n', double(ok));
if isfield(out,'Manifest')
    try
        fprintf('CodexLongRunResultOkManifest=%d\n', double(logical(out.Manifest.ResultOk)));
        fprintf('CodexLongRunRequiredFailureCount=%g\n', double(out.Manifest.RequiredFailureCount));
    catch
    end
end
assert(ok, 'Long-run scenario returned Ok=false; inspect truth-contract artifacts and logs.');
"@
    Set-Content -LiteralPath $driverPath -Value $driverText -Encoding UTF8
    $matlabCmd = "run('$($driverPath.Replace("'", "''"))')"

    Write-Host "[$(Get-Date -Format o)] Attempt $AttemptIndex launching $AttemptTag"
    Write-Host "MATLAB: $MatlabExe"
    Write-Host "Scenario: $ScenarioPath"
    Write-Host "Log: $logPath"

    $argumentText = '-batch "' + $matlabCmd.Replace('"', '\"') + '"'
    $proc = Start-Process -FilePath $MatlabExe -ArgumentList $argumentText -WorkingDirectory $RepoRoot -RedirectStandardOutput $logPath -RedirectStandardError "$logPath.err" -PassThru -WindowStyle Hidden
    $attemptStarted = Get-Date
    while (-not $proc.HasExited) {
        Start-Sleep -Seconds $PollSeconds
        Write-Host "[$(Get-Date -Format o)] Attempt $AttemptIndex still running; PID=$($proc.Id)"
        if (Test-Path -LiteralPath $logPath) {
            Get-Content -LiteralPath $logPath -Tail 12 | ForEach-Object { Write-Host "MATLAB> $_" }
        }
        try {
            & (Join-Path $PSScriptRoot "monitor_lls_run.ps1") -Latest -Once -Quiet
        } catch {
            Write-Host "Monitor unavailable: $($_.Exception.Message)"
        }
        if ($MaxWallMinutes -gt 0 -and ((Get-Date) - $attemptStarted).TotalMinutes -ge $MaxWallMinutes) {
            Write-Host "[$(Get-Date -Format o)] Attempt $AttemptIndex exceeded MaxWallMinutes=$MaxWallMinutes; stopping PID=$($proc.Id) for supervised root-cause review."
            try { Stop-Process -Id $proc.Id -Force -ErrorAction Stop } catch {}
            try {
                Get-Process -Name MATLAB,matlab -ErrorAction SilentlyContinue |
                    Where-Object { $_.StartTime -ge $attemptStarted.AddSeconds(-2) } |
                    Stop-Process -Force -ErrorAction SilentlyContinue
            } catch {}
            $proc.WaitForExit()
            return $false
        }
    }

    $exitCode = $proc.ExitCode
    Write-Host "[$(Get-Date -Format o)] Attempt $AttemptIndex exited with code $exitCode"
    if (Test-Path -LiteralPath "$logPath.err") {
        Get-Content -LiteralPath "$logPath.err" -Tail 40 | ForEach-Object { Write-Host "MATLAB-ERR> $_" }
    }
    if ($exitCode -ne 0) {
        return $false
    }

    python (Join-Path $PSScriptRoot "validate_lls_run_outputs.py") --base-url $BaseUrl --run-tag $AttemptTag --strict
    return ($LASTEXITCODE -eq 0)
}

$success = $false
for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
    $attemptTag = if ($attempt -eq 1) { $RunTag } else { "$RunTag`_attempt$attempt" }
    $success = Invoke-LongRunAttempt -AttemptTag $attemptTag -AttemptIndex $attempt
    if ($success) {
        Write-Host "Long-run attempt succeeded: $attemptTag"
        if (-not $SkipReplay) {
            $replayTag = "$attemptTag`_replay"
            Write-Host "Launching deterministic replay: $replayTag"
            $replayOk = Invoke-LongRunAttempt -AttemptTag $replayTag -AttemptIndex 1
            if (-not $replayOk) {
                throw "Deterministic replay failed for $replayTag"
            }
        }
        exit 0
    }
    Write-Host "Attempt $attempt failed. Preserve logs and patch the root cause before rerunning this script."
}

throw "Long-run scenario failed after $MaxAttempts attempts. Check $LogDir for attempt logs."
