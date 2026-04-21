param(
    [string]$BindHost = "0.0.0.0",
    [int]$FrontendPort = 62906,
    [int]$BackendPort = 62907,
    [string]$PublicHost = "",
    [ValidateSet("auto", "threading", "waitress")]
    [string]$Server = "auto",
    [int]$Threads = 32,
    [string]$NginxExe = "",
    [string]$CacheRoot = "",
    [switch]$NoBrowser,
    [switch]$SkipFirewallRule
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$dashboardLauncher = Join-Path $PSScriptRoot "start_lls_web_dashboard.ps1"
$templatePath = Join-Path $PSScriptRoot "deploy\\nginx\\lls_dashboard_proxy_cache.conf.template"
$runtimeRoot = Join-Path $repoRoot "tmp_web_runs"
if (-not (Test-Path $runtimeRoot)) {
    New-Item -ItemType Directory -Path $runtimeRoot | Out-Null
}

function Resolve-NginxExe {
    param([string]$RequestedPath)

    $candidates = @()
    if (-not [string]::IsNullOrWhiteSpace($RequestedPath)) { $candidates += $RequestedPath }
    if (-not [string]::IsNullOrWhiteSpace($env:SIXGR_NGINX_EXE)) { $candidates += $env:SIXGR_NGINX_EXE }
    try {
        $cmd = Get-Command nginx -ErrorAction SilentlyContinue
        if ($cmd) { $candidates += $cmd.Source }
    }
    catch {}
    $candidates += @(
        "C:\\nginx\\nginx.exe",
        "C:\\tools\\nginx\\nginx.exe",
        (Join-Path $repoRoot ".tools\\nginx\\nginx.exe")
    )
    foreach ($candidate in $candidates) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path $candidate)) {
            return (Resolve-Path $candidate).Path
        }
    }
    return ""
}

function Ensure-DashboardFirewallRule {
    param([int]$LocalPort)
    if ($SkipFirewallRule) { return }
    if ($BindHost -match '^(127\.|localhost$)') { return }
    $ruleName = "SixGR LLS Dashboard TCP $LocalPort"
    try {
        $existing = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
        if (-not $existing) {
            New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -Action Allow -Protocol TCP -LocalPort $LocalPort -Profile Domain,Private | Out-Null
            Write-Host "[lls-edge] Added Windows firewall rule '$ruleName'."
        }
    }
    catch {
        Write-Warning "Could not create the Windows firewall rule for TCP port $LocalPort. $($_.Exception.Message)"
    }
}

function Start-BackendDashboard {
    $stdout = Join-Path $runtimeRoot "dashboard_edge_backend.out.log"
    $stderr = Join-Path $runtimeRoot "dashboard_edge_backend.err.log"
    $command = "& '$dashboardLauncher' -BindHost '127.0.0.1' -Port $BackendPort -Server $Server -Threads $Threads -NoBrowser"
    if (-not [string]::IsNullOrWhiteSpace($PublicHost)) {
        $command += " -PublicHost '$PublicHost'"
    }
    Start-Process powershell -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-Command', $command) -WorkingDirectory $repoRoot -RedirectStandardOutput $stdout -RedirectStandardError $stderr | Out-Null
    Write-Host "[lls-edge] Backend dashboard launch issued on 127.0.0.1:$BackendPort using server backend '$Server'."
}

function Render-NginxConfig {
    param(
        [string]$TemplatePath,
        [string]$OutputPath,
        [string]$ResolvedCacheRoot
    )

    $content = Get-Content $TemplatePath -Raw
    $escapedCacheRoot = ($ResolvedCacheRoot -replace '\\', '/')
    $content = $content.Replace("__CACHE_ROOT__", $escapedCacheRoot)
    $content = $content.Replace("__BACKEND_PORT__", [string]$BackendPort)
    $content = $content.Replace("__FRONTEND_PORT__", [string]$FrontendPort)
    Set-Content -Path $OutputPath -Value $content -Encoding UTF8
}

$resolvedNginx = Resolve-NginxExe -RequestedPath $NginxExe
if ([string]::IsNullOrWhiteSpace($resolvedNginx)) {
    Write-Warning "[lls-edge] nginx.exe was not found. Falling back to the direct dashboard launcher with the selected backend."
    $fallbackArgs = @('-BindHost', $BindHost, '-Port', [string]$FrontendPort, '-Server', $Server, '-Threads', [string]$Threads)
    if (-not [string]::IsNullOrWhiteSpace($PublicHost)) { $fallbackArgs += @('-PublicHost', $PublicHost) }
    if ($NoBrowser) { $fallbackArgs += '-NoBrowser' }
    if ($SkipFirewallRule) { $fallbackArgs += '-SkipFirewallRule' }
    & $dashboardLauncher @fallbackArgs
    exit $LASTEXITCODE
}

if ([string]::IsNullOrWhiteSpace($CacheRoot)) {
    $CacheRoot = Join-Path $runtimeRoot "nginx_artifact_cache"
}
if (-not (Test-Path $CacheRoot)) {
    New-Item -ItemType Directory -Path $CacheRoot -Force | Out-Null
}

$configPath = Join-Path $runtimeRoot "lls_dashboard_proxy_cache.conf"
Render-NginxConfig -TemplatePath $templatePath -OutputPath $configPath -ResolvedCacheRoot (Resolve-Path $CacheRoot).Path

Ensure-DashboardFirewallRule -LocalPort $FrontendPort
Start-BackendDashboard
Start-Sleep -Seconds 4

$stdout = Join-Path $runtimeRoot "dashboard_edge_nginx.out.log"
$stderr = Join-Path $runtimeRoot "dashboard_edge_nginx.err.log"
$nginxArgs = @('-p', (Split-Path $configPath -Parent), '-c', $configPath)
Start-Process -FilePath $resolvedNginx -ArgumentList $nginxArgs -WorkingDirectory (Split-Path $resolvedNginx -Parent) -RedirectStandardOutput $stdout -RedirectStandardError $stderr | Out-Null

if ($BindHost -eq '0.0.0.0') {
    $frontendHost = '127.0.0.1'
} else {
    $frontendHost = $BindHost
}

Write-Host "[lls-edge] Edge stack is starting."
Write-Host "[lls-edge] Frontend URL : http://$frontendHost:$FrontendPort/"
Write-Host "[lls-edge] Backend URL  : http://127.0.0.1:$BackendPort/"
Write-Host "[lls-edge] nginx exe    : $resolvedNginx"
Write-Host "[lls-edge] nginx config : $configPath"
Write-Host "[lls-edge] cache root   : $CacheRoot"
Write-Host "[lls-edge] Artifact/image requests now flow through nginx with immutable caching on /artifact/* while the Python dashboard remains the orchestration and API backend."
