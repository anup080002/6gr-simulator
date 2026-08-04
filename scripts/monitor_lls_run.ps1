param(
    [long]$RunId = 0,
    [string]$RunTag = "",
    [switch]$Latest,
    [switch]$Once,
    [switch]$Quiet,
    [string]$BaseUrl = "",
    [string]$Username = "admin",
    [string]$Password = "admin",
    [int]$PollSeconds = 10,
    [int]$RequestTimeoutSec = 180
)

$ErrorActionPreference = "Stop"

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

$Session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
Invoke-WebRequest -Uri "$BaseUrl/login" -Method Post -Body @{ username = $Username; password = $Password; next = "/home" } -WebSession $Session -UseBasicParsing -TimeoutSec $RequestTimeoutSec | Out-Null

function Get-Json($Url) {
    Invoke-RestMethod -Uri $Url -UseBasicParsing -TimeoutSec $RequestTimeoutSec -WebSession $Session
}

function Resolve-RunId {
    if ($RunId -gt 0) { return $RunId }
    if (-not [string]::IsNullOrWhiteSpace($RunTag)) {
        $tagRuns = Get-Json "$BaseUrl/api/runs?run_tag=$([uri]::EscapeDataString($RunTag))&limit=1"
        if ($tagRuns.runs.Count -ge 1) {
            return [long]$tagRuns.runs[0].run_id
        }
    }
    $runs = Get-Json "$BaseUrl/api/runs?limit=25"
    if ($runs.runs.Count -lt 1) { throw "No sim_runs rows are visible through $BaseUrl/api/runs" }
    $running = @($runs.runs | Where-Object { [string]$_.status_text -match '^running' })
    if ($running.Count -ge 1) {
        return [long]$running[0].run_id
    }
    return [long]$runs.runs[0].run_id
}

do {
    $rid = Resolve-RunId
    $live = Get-Json "$BaseUrl/api/run/$rid/live"
    $run = $live.run
    $counts = $live.counts
    $debug = $live.debug
    $line = "run_id=$rid status=$($run.status_text) result_ok=$($run.result_ok) required_failures=$($run.required_failure_count) artifacts=$($counts.artifacts_total) tables=$($counts.tables_total) images=$($counts.images_total) logs=$($counts.logs_total) truth_contract=$($debug.runtime_truth_contract_ok)"
    if (-not $Quiet) {
        Write-Host "[$(Get-Date -Format o)] $line"
        ($live.logs_recent | Select-Object -Last 5) | ForEach-Object {
            Write-Host ("LOG {0} {1}" -f $_.level_str, $_.message_text)
        }
    } else {
        Write-Host "[$(Get-Date -Format o)] $line"
    }
    if ($Once) { break }
    Start-Sleep -Seconds $PollSeconds
} while ($true)
