param(
    [string]$BindHost = "",
    [int]$Port = 0,
    [string]$PublicHost = "",
    [ValidateSet("auto", "threading", "waitress")]
    [string]$Server = "auto",
    [int]$Threads = 32,
    [switch]$NoBrowser,
    [switch]$SkipFirewallRule,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$PassthroughArgs
)

$ErrorActionPreference = "Stop"

if (-not $env:MYSQL_HOST) { $env:MYSQL_HOST = "localhost" }
if (-not $env:MYSQL_PORT) { $env:MYSQL_PORT = "3306" }
if (-not $env:MYSQL_USER) { $env:MYSQL_USER = "root" }
if (-not $env:MYSQL_PASSWORD) { $env:MYSQL_PASSWORD = "root" }
if (-not $env:MYSQL_DATABASE) { $env:MYSQL_DATABASE = "sixgr_results" }
if ([string]::IsNullOrWhiteSpace($BindHost)) {
    $BindHost = if ([string]::IsNullOrWhiteSpace($env:SIXGR_DASHBOARD_HOST)) { "0.0.0.0" } else { $env:SIXGR_DASHBOARD_HOST }
}
if ($Port -le 0) {
    $Port = if ([string]::IsNullOrWhiteSpace($env:SIXGR_DASHBOARD_PORT)) { 62906 } else { [int]$env:SIXGR_DASHBOARD_PORT }
}
if ([string]::IsNullOrWhiteSpace($PublicHost)) {
    $PublicHost = $env:SIXGR_DASHBOARD_PUBLIC_HOST
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $PSScriptRoot "lls_web_dashboard.py"
$matlabPath = if ([string]::IsNullOrWhiteSpace($env:SIXGR_MATLAB_EXE)) { "C:\Program Files\MATLAB\R2024a\bin\matlab.exe" } else { $env:SIXGR_MATLAB_EXE }

if (-not (Test-Path $matlabPath)) {
    throw "Required MATLAB R2024a executable is missing: $matlabPath"
}

function Ensure-DashboardFirewallRule {
    param(
        [Parameter(Mandatory = $true)]
        [int]$LocalPort
    )

    if ($SkipFirewallRule) {
        return
    }
    if ($BindHost -match '^(127\.|localhost$)') {
        return
    }
    $ruleName = "SixGR LLS Dashboard TCP $LocalPort"
    try {
        $existing = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
        if (-not $existing) {
            New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -Action Allow -Protocol TCP -LocalPort $LocalPort -Profile Domain,Private | Out-Null
            Write-Host "[lls-web] Added Windows firewall rule '$ruleName' for intranet access."
        } else {
            Write-Host "[lls-web] Windows firewall rule '$ruleName' already exists."
        }
    }
    catch {
        Write-Warning "Could not create the Windows firewall rule for TCP port $LocalPort. Remote intranet clients may still be blocked. $($_.Exception.Message)"
    }
}

function Test-WebDashboardPython {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Command
    )

    $probe = "import sys; import yaml; print(sys.executable)"
    $prefix = @()
    if ($Command.Length -gt 1) {
        $prefix = $Command[1..($Command.Length - 1)]
    }
    try {
        $exe = & $Command[0] $prefix -c $probe 2>$null
        if ($LASTEXITCODE -eq 0 -and $exe) {
            return [pscustomobject]@{
                Ok = $true
                Executable = ($exe | Select-Object -Last 1).Trim()
                Command = $Command
            }
        }
    }
    catch {
    }

    return [pscustomobject]@{
        Ok = $false
        Executable = ""
        Command = $Command
    }
}

$pythonCandidates = @()
if ($env:PYTHON_EXE) {
    $pythonCandidates += ,@($env:PYTHON_EXE)
}
if (Get-Command py -ErrorAction SilentlyContinue) {
    $pythonCandidates += ,@("py", "-3")
}
if (Get-Command python -ErrorAction SilentlyContinue) {
    $pythonCandidates += ,@((Get-Command python).Source)
}

$selected = $null
foreach ($candidate in $pythonCandidates) {
    $probe = Test-WebDashboardPython -Command $candidate
    if ($probe.Ok) {
        $selected = $probe
        break
    }
}

if (-not $selected) {
    $installHint = if ($env:PYTHON_EXE) {
        "`"$($env:PYTHON_EXE)`" -m pip install pyyaml"
    }
    elseif (Get-Command py -ErrorAction SilentlyContinue) {
        "py -3 -m pip install pyyaml"
    }
    else {
        "python -m pip install pyyaml"
    }
    throw "No Python runtime with PyYAML was found for the web dashboard. Install the dependency with: $installHint"
}

Write-Host "[lls-web] Python runtime: $($selected.Executable)"
$selectedPrefix = @()
if ($selected.Command.Length -gt 1) {
    $selectedPrefix = $selected.Command[1..($selected.Command.Length - 1)]
}
$mysqlProbe = "import mysql.connector"
try {
    & $selected.Command[0] $selectedPrefix -c $mysqlProbe 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "mysql-connector-python is not installed for this Python runtime. The dashboard will still start in results-folder/filesystem mode; database-backed pages will report MySQL unavailable until installed."
    }
}
catch {
    Write-Warning "Could not probe mysql-connector-python. The dashboard will still start; database-backed pages may report MySQL unavailable."
}
Write-Host "[lls-web] MATLAB runtime: $matlabPath"
Write-Host "[lls-web] Dashboard bind host: $BindHost"
Write-Host "[lls-web] Dashboard port: $Port"
Write-Host "[lls-web] HTTP backend: $Server"
Write-Host "[lls-web] Worker threads: $Threads"
$env:SIXGR_DASHBOARD_HOST = $BindHost
$env:SIXGR_DASHBOARD_PORT = [string]$Port
$env:SIXGR_DASHBOARD_SERVER = $Server
$env:SIXGR_DASHBOARD_THREADS = [string]$Threads
Ensure-DashboardFirewallRule -LocalPort $Port
$dashboardArgs = @("--host", $BindHost, "--port", [string]$Port, "--server", $Server, "--threads", [string]$Threads)
if (-not [string]::IsNullOrWhiteSpace($PublicHost)) {
    $dashboardArgs += @("--public-host", $PublicHost)
}
if ($NoBrowser) {
    $dashboardArgs += "--no-browser"
}
if ($PassthroughArgs) {
    $dashboardArgs += $PassthroughArgs
}
& $selected.Command[0] $selectedPrefix $scriptPath $dashboardArgs
