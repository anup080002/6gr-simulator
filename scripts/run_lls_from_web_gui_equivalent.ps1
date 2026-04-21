param(
    [string]$BaseUrl = "",
    [string]$Scenario = "lls_3gpp_rel20_anchor_4ghz_100mhz_waveform_honest_200ue_1frame.yaml",
    [string]$Username = "admin",
    [string]$Password = "admin",
    [string]$RunTag = "",
    [int]$MaxAttempts = 10,
    [int]$LookupTimeoutSec = 180
)

function Resolve-DashboardBaseUrl {
    param([string]$Candidate)
    if (-not [string]::IsNullOrWhiteSpace($Candidate)) {
        return $Candidate.TrimEnd('/')
    }
    if (-not [string]::IsNullOrWhiteSpace($env:SIXGR_DASHBOARD_BASE_URL)) {
        return $env:SIXGR_DASHBOARD_BASE_URL.TrimEnd('/')
    }
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
    $listenerPath = Join-Path $repoRoot "tmp_web_runs\dashboard_listener.json"
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

if ([string]::IsNullOrWhiteSpace($RunTag)) {
    $RunTag = "webgui_rel20_4ghz_100mhz_200ue_1frame_" + (Get-Date -Format "yyyyMMdd_HHmmss")
}

$session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
$loginBody = @{
    username = $Username
    password = $Password
    next = "/home"
}
Invoke-WebRequest -Uri ($BaseUrl.TrimEnd('/') + "/login") -Method Post -Body $loginBody -WebSession $session -MaximumRedirection 5 | Out-Null

$runBody = @{
    scenario = $Scenario
    execution_mode = "LLS"
    run_tag = $RunTag
}

Invoke-WebRequest -Uri ($BaseUrl.TrimEnd('/') + "/run") -Method Post -Body $runBody -WebSession $session -MaximumRedirection 0 -ErrorAction SilentlyContinue | Out-Null
Write-Host "Submitted /run for scenario $Scenario with run_tag $RunTag"
$runId = $null
$deadline = (Get-Date).AddSeconds([Math]::Max(5, $LookupTimeoutSec))
do {
    Start-Sleep -Seconds 2
    try {
        $lookup = Invoke-RestMethod -Uri ($BaseUrl.TrimEnd('/') + "/api/runs?run_tag=" + [uri]::EscapeDataString($RunTag) + "&limit=1") -WebSession $session -TimeoutSec 30
        if ($lookup -and $lookup.runs -and $lookup.runs.Count -ge 1) {
            $candidate = $lookup.runs[0]
            if ($candidate.run_tag -eq $RunTag -and [int]$candidate.run_id -gt 0) {
                $runId = [int]$candidate.run_id
                break
            }
        }
    } catch {
    }
} while ((Get-Date) -lt $deadline)

if ($runId) {
    Write-Host "Resolved run_id $runId for run_tag $RunTag"
    Write-Host "Use monitor_lls_run.ps1 -RunId $runId against $BaseUrl"
} else {
    Write-Host "Run row for run_tag $RunTag is not visible yet."
    Write-Host "Use monitor_lls_run.ps1 -RunTag $RunTag against $BaseUrl"
}
