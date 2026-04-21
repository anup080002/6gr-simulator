param(
    [string]$BindHost = "",
    [int]$Port = 0,
    [string]$PublicHost = "",
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
$matlabPath = "C:\Program Files\MATLAB\R2023b\bin\matlab.exe"

if (-not (Test-Path $matlabPath)) {
    throw "Required MATLAB R2023b executable is missing: $matlabPath"
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

    $probe = "import sys; import yaml; import mysql.connector; print(sys.executable)"
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
        "`"$($env:PYTHON_EXE)`" -m pip install mysql-connector-python pyyaml"
    }
    elseif (Get-Command py -ErrorAction SilentlyContinue) {
        "py -3 -m pip install mysql-connector-python pyyaml"
    }
    else {
        "python -m pip install mysql-connector-python pyyaml"
    }
    throw "No Python runtime with both PyYAML and mysql-connector-python was found for the web dashboard. Install the dependencies with: $installHint"
}

Write-Host "[lls-web] Python runtime: $($selected.Executable)"
Write-Host "[lls-web] MATLAB runtime: $matlabPath"
Write-Host "[lls-web] Dashboard bind host: $BindHost"
Write-Host "[lls-web] Dashboard port: $Port"
$env:SIXGR_DASHBOARD_HOST = $BindHost
$env:SIXGR_DASHBOARD_PORT = [string]$Port
Ensure-DashboardFirewallRule -LocalPort $Port
$selectedPrefix = @()
if ($selected.Command.Length -gt 1) {
    $selectedPrefix = $selected.Command[1..($selected.Command.Length - 1)]
}
$dashboardArgs = @("--host", $BindHost, "--port", [string]$Port)
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
