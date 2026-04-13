$ErrorActionPreference = "Stop"

if (-not $env:MYSQL_HOST) { $env:MYSQL_HOST = "localhost" }
if (-not $env:MYSQL_PORT) { $env:MYSQL_PORT = "3306" }
if (-not $env:MYSQL_USER) { $env:MYSQL_USER = "root" }
if (-not $env:MYSQL_PASSWORD) { $env:MYSQL_PASSWORD = "root" }
if (-not $env:MYSQL_DATABASE) { $env:MYSQL_DATABASE = "sixgr_results" }

$repoRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $PSScriptRoot "lls_web_dashboard.py"
$matlabPath = "C:\Program Files\MATLAB\R2023b\bin\matlab.exe"

if (-not (Test-Path $matlabPath)) {
    throw "Required MATLAB R2023b executable is missing: $matlabPath"
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
$selectedPrefix = @()
if ($selected.Command.Length -gt 1) {
    $selectedPrefix = $selected.Command[1..($selected.Command.Length - 1)]
}
& $selected.Command[0] $selectedPrefix $scriptPath @args
