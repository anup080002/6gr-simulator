param(
    [int]$RunId = 0,
    [switch]$Latest,
    [switch]$Once,
    [switch]$Quiet,
    [string]$BaseUrl = "http://127.0.0.1:62906",
    [string]$Username = "admin",
    [string]$Password = "admin",
    [int]$PollSeconds = 10
)

$ErrorActionPreference = "Stop"

$Session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
Invoke-WebRequest -Uri "$BaseUrl/login" -Method Post -Body @{ username = $Username; password = $Password; next = "/home" } -WebSession $Session -UseBasicParsing -TimeoutSec 5 | Out-Null

function Get-Json($Url) {
    Invoke-RestMethod -Uri $Url -UseBasicParsing -TimeoutSec 5 -WebSession $Session
}

function Resolve-RunId {
    if ($RunId -gt 0) { return $RunId }
    $runs = Get-Json "$BaseUrl/api/runs?limit=1"
    if ($runs.runs.Count -lt 1) { throw "No sim_runs rows are visible through $BaseUrl/api/runs" }
    return [int]$runs.runs[0].run_id
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
