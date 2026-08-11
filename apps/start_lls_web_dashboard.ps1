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

$repoRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $PSScriptRoot "lls_web_dashboard.py"
$requirementsPath = Join-Path $PSScriptRoot "requirements-webgui.txt"
$venvRoot = Join-Path $PSScriptRoot ".webgui-venv"
$venvPython = Join-Path $venvRoot "Scripts\python.exe"

function Import-LocalDashboardEnvironment {
    # Authentication is kept in the ignored .env.auth file and loaded first.
    # General deployment settings remain in the ignored .env file. Existing
    # process-level variables retain the highest priority.
    foreach ($fileName in @(".env.auth", ".env")) {
        $envPath = Join-Path $PSScriptRoot $fileName
        if (-not (Test-Path -LiteralPath $envPath)) {
            continue
        }
        foreach ($rawLine in Get-Content -LiteralPath $envPath) {
            $line = $rawLine.Trim()
            if (-not $line -or $line.StartsWith("#") -or -not $line.Contains("=")) {
                continue
            }
            $parts = $line.Split("=", 2)
            $key = $parts[0].Trim()
            if ($key -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') {
                continue
            }
            if (Test-Path -LiteralPath "Env:$key") {
                continue
            }
            $value = $parts[1].Trim()
            if ($value.Length -ge 2 -and
                (($value.StartsWith('"') -and $value.EndsWith('"')) -or
                 ($value.StartsWith("'") -and $value.EndsWith("'")))) {
                $value = $value.Substring(1, $value.Length - 2)
            }
            Set-Item -LiteralPath "Env:$key" -Value $value
        }
    }
}

function Resolve-MatlabExecutable {
    if (-not [string]::IsNullOrWhiteSpace($env:SIXGR_MATLAB_EXE) -and
        (Test-Path -LiteralPath $env:SIXGR_MATLAB_EXE)) {
        return (Resolve-Path -LiteralPath $env:SIXGR_MATLAB_EXE).Path
    }
    $pathCommand = Get-Command matlab -ErrorAction SilentlyContinue
    if ($pathCommand -and (Test-Path -LiteralPath $pathCommand.Source)) {
        return $pathCommand.Source
    }
    $installRoots = @(
        (Join-Path ${env:ProgramFiles} "MATLAB"),
        (Join-Path ${env:ProgramFiles(x86)} "MATLAB")
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }
    $candidates = foreach ($installRoot in $installRoots) {
        Get-ChildItem -LiteralPath $installRoot -Directory -Filter "R20???" -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^R\d{4}[ab]$' } |
            ForEach-Object { Join-Path $_.FullName "bin\matlab.exe" } |
            Where-Object { Test-Path -LiteralPath $_ }
    }
    return $candidates | Sort-Object -Descending | Select-Object -First 1
}

function Resolve-BasePython {
    $candidates = @()
    if (-not [string]::IsNullOrWhiteSpace($env:PYTHON_EXE)) {
        $candidates += [pscustomobject]@{ Executable = $env:PYTHON_EXE; Prefix = @() }
    }
    $pythonCommand = Get-Command python -ErrorAction SilentlyContinue
    if ($pythonCommand) {
        $candidates += [pscustomobject]@{ Executable = $pythonCommand.Source; Prefix = @() }
    }
    $pyCommand = Get-Command py -ErrorAction SilentlyContinue
    if ($pyCommand) {
        $candidates += [pscustomobject]@{ Executable = $pyCommand.Source; Prefix = @("-3") }
    }
    foreach ($candidate in $candidates) {
        try {
            $prefixArgs = @($candidate.Prefix)
            & $candidate.Executable $prefixArgs -c "import sys; raise SystemExit(0 if sys.version_info >= (3,10) else 1)" 2>$null
            if ($LASTEXITCODE -eq 0) {
                return $candidate
            }
        }
        catch {
        }
    }
    return $null
}

function Ensure-DashboardPython {
    $venvPythonReady = $false
    if (Test-Path -LiteralPath $venvPython) {
        try {
            & $venvPython -c "import sys; raise SystemExit(0 if sys.version_info >= (3,10) else 1)" 2>$null
            $venvPythonReady = $LASTEXITCODE -eq 0
            if ($venvPythonReady) {
                & $venvPython -c "import yaml,mysql.connector,waitress" 2>$null
                if ($LASTEXITCODE -eq 0) {
                    return $venvPython
                }
            }
        }
        catch {
            $venvPythonReady = $false
        }
    }
    if (-not $venvPythonReady) {
        $basePython = Resolve-BasePython
        if (-not $basePython) {
            throw "Python 3.10 or newer was not found. Install Python 3 or set PYTHON_EXE."
        }
        $prefixArgs = @($basePython.Prefix)
        & $basePython.Executable $prefixArgs -m venv --clear $venvRoot
        if ($LASTEXITCODE -ne 0) {
            throw "Could not create the local WebGUI Python environment."
        }
    }
    & $venvPython -m pip install --disable-pip-version-check -q -r $requirementsPath
    if ($LASTEXITCODE -ne 0) {
        throw "Could not install the original WebGUI dependencies."
    }
    return $venvPython
}

function Ensure-DashboardFirewallRule {
    param([int]$LocalPort)
    if ($SkipFirewallRule -or $BindHost -match '^(127\.|localhost$)') {
        return
    }
    $ruleName = "SixGR LLS Dashboard TCP $LocalPort"
    try {
        $existing = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
        if (-not $existing) {
            New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -Action Allow `
                -Protocol TCP -LocalPort $LocalPort -Profile Domain,Private | Out-Null
            Write-Host "[lls-web] Added Windows firewall rule '$ruleName'."
        }
    }
    catch {
        Write-Warning "Could not create the firewall rule for TCP $LocalPort. $($_.Exception.Message)"
    }
}

Import-LocalDashboardEnvironment

if (-not $env:MYSQL_HOST) { $env:MYSQL_HOST = "127.0.0.1" }
if (-not $env:MYSQL_PORT) { $env:MYSQL_PORT = "3306" }
if (-not $env:MYSQL_USER) { $env:MYSQL_USER = "root" }
if (-not $env:MYSQL_DATABASE) { $env:MYSQL_DATABASE = "sixgr_results" }
if ([string]::IsNullOrWhiteSpace($BindHost)) {
    $BindHost = if ($env:SIXGR_DASHBOARD_HOST) { $env:SIXGR_DASHBOARD_HOST } else { "127.0.0.1" }
}
if ($Port -le 0) {
    $Port = if ($env:SIXGR_DASHBOARD_PORT) { [int]$env:SIXGR_DASHBOARD_PORT } else { 62906 }
}
if ([string]::IsNullOrWhiteSpace($PublicHost)) {
    $PublicHost = $env:SIXGR_DASHBOARD_PUBLIC_HOST
}

$existingListener = Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue |
    Select-Object -First 1
if ($existingListener) {
    $existingUrl = "http://127.0.0.1:$Port/"
    try {
        $status = Invoke-RestMethod -Uri "${existingUrl}api/status" -TimeoutSec 5
        if ($status -and $status.PSObject.Properties.Name -contains "matlab_available") {
            Write-Host "[lls-web] The original WebGUI is already running at $existingUrl"
            if (-not $NoBrowser) {
                Start-Process $existingUrl | Out-Null
            }
            exit 0
        }
    }
    catch {
    }
    throw "TCP port $Port is already used by another process."
}

$matlabPath = Resolve-MatlabExecutable
if ($matlabPath) {
    $env:SIXGR_MATLAB_EXE = $matlabPath
    Write-Host "[lls-web] MATLAB runtime: $matlabPath"
} else {
    Write-Warning "MATLAB was not found automatically. The dashboard will open for existing results, but Run is disabled until SIXGR_MATLAB_EXE or PATH is configured."
}

$dashboardPython = Ensure-DashboardPython
Write-Host "[lls-web] Python runtime: $dashboardPython"
Write-Host "[lls-web] Dashboard URL: http://127.0.0.1:$Port/"

$env:SIXGR_DASHBOARD_HOST = $BindHost
$env:SIXGR_DASHBOARD_PORT = [string]$Port
$env:SIXGR_DASHBOARD_SERVER = $Server
$env:SIXGR_DASHBOARD_THREADS = [string]$Threads
Ensure-DashboardFirewallRule -LocalPort $Port

$dashboardArgs = @(
    $scriptPath,
    "--host", $BindHost,
    "--port", [string]$Port,
    "--server", $Server,
    "--threads", [string]$Threads
)
if (-not [string]::IsNullOrWhiteSpace($PublicHost)) {
    $dashboardArgs += @("--public-host", $PublicHost)
}
if ($NoBrowser) {
    $dashboardArgs += "--no-browser"
}
if ($PassthroughArgs) {
    $dashboardArgs += $PassthroughArgs
}
& $dashboardPython $dashboardArgs
