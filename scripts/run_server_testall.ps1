[CmdletBinding()]
param(
    [string]$MatlabExe = 'matlab',
    [switch]$PreflightOnly,
    [string[]]$Tests = @(),
    [switch]$AllowDirty
)

# Windows PowerShell 5.1 and PowerShell 7. Logs are always repo-local.
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$runName = 'testall_' + [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ') + '_' + [guid]::NewGuid().ToString('N').Substring(0,8)
$logDir = Join-Path $repoRoot ('logs\' + $runName)
New-Item -ItemType Directory -Path $logDir | Out-Null
$metadataPath = Join-Path $logDir 'launcher.json'
$metadata = [ordered]@{
    schema_version = 1; status = 'starting'; started_utc = [DateTime]::UtcNow.ToString('o')
    repository = $repoRoot; matlab_requested = $MatlabExe
    powershell_version = $PSVersionTable.PSVersion.ToString()
    preflight_only = [bool]$PreflightOnly; selected_tests = @($Tests)
    allow_dirty = [bool]$AllowDirty; suite_pass = $false
}
$exitCode = 1
Push-Location -LiteralPath $repoRoot
try {
    $metadata | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $metadataPath -Encoding UTF8
    if ($PreflightOnly -and $Tests.Count) { throw 'PreflightOnly cannot be combined with Tests.' }
    foreach ($testName in $Tests) {
        if ($testName -notmatch '^[A-Za-z][A-Za-z0-9_]*$') { throw "Invalid MATLAB test name: $testName" }
    }
    $metadata.git_commit = (& git rev-parse HEAD | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Use a Git clone, including Git LFS evidence, not a source ZIP.' }
    $statusBefore = (& git status --porcelain=v1 --untracked-files=normal | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect Git worktree.' }
    $metadata.git_status_before = $statusBefore
    if ($statusBefore -and -not $AllowDirty) { throw 'Commit or preserve local edits first. This launcher requires a clean checkout (AllowDirty is diagnostic only).' }
    $command = Get-Command -Name $MatlabExe -CommandType Application -ErrorAction Stop | Select-Object -First 1
    $metadata.matlab_executable = $command.Source
    $rootLiteral = $repoRoot.Replace("'", "''").Replace('\','/')
    $logLiteral = $logDir.Replace("'", "''").Replace('\','/')
    $namesLiteral = '{' + (($Tests | ForEach-Object { "'$_'" }) -join ',') + '}'
    $preflightLiteral = if ($PreflightOnly) { 'true' } else { 'false' }
    $batch = "cd('$rootLiteral'); addpath(fullfile(pwd,'scripts')); run_server_testall('$logLiteral',$preflightLiteral,$namesLiteral);"
    $metadata.batch = $batch
    $metadata.status = 'running'
    $metadata | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $metadataPath -Encoding UTF8
    Write-Host "Logs: $logDir"
    Write-Host "MATLAB: $($command.Source) | revision: $($metadata.git_commit)"
    # -wait is required for a reliable native process exit code on Windows.
    & $command.Source -wait -logfile (Join-Path $logDir 'matlab.log') -batch $batch
    $exitCode = $LASTEXITCODE
    $metadata.matlab_exit_code = $exitCode
    $headAfter = (& git rev-parse HEAD | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Cannot read terminal Git revision.' }
    $statusAfter = (& git status --porcelain=v1 --untracked-files=normal | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Cannot read terminal Git status.' }
    $metadata.git_status_after = $statusAfter
    $metadata.git_commit_after = $headAfter
    if ($headAfter -ne $metadata.git_commit -or $statusAfter -ne $statusBefore) {
        throw 'Source changed while MATLAB was running. These results do not qualify one frozen revision.'
    }
    $summaryPath = Join-Path $logDir 'summary.json'
    if (-not (Test-Path -LiteralPath $summaryPath)) { throw 'MATLAB did not write a terminal summary; inspect matlab.log for startup errors or a crash.' }
    $summary = Get-Content -LiteralPath $summaryPath -Raw | ConvertFrom-Json
    if ($exitCode -ne 0 -or $summary.status -ne 'passed') { throw "Validation did not pass (MATLAB exit $exitCode). See summary.json and matlab.log." }
    $metadata.status = if ($PreflightOnly) { 'preflight_passed_not_testall' } elseif ($Tests.Count) { 'focused_passed_not_testall' } else { 'testall_passed' }
    $metadata.suite_pass = (-not $PreflightOnly -and $Tests.Count -eq 0 -and -not $statusBefore)
    $exitCode = 0
} catch {
    $metadata.status = 'failed_or_incomplete'
    $metadata.error = $_.Exception.Message
    $exitCode = 1
    $_ | Out-String | Set-Content -LiteralPath (Join-Path $logDir 'launcher_error.txt') -Encoding UTF8
    Write-Warning $_.Exception.Message
} finally {
    $metadata.finished_utc = [DateTime]::UtcNow.ToString('o')
    $metadata.launcher_exit_code = $exitCode
    $metadata | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $metadataPath -Encoding UTF8
    Pop-Location
    try {
        $archive = $logDir + '.zip'
        Compress-Archive -LiteralPath $logDir -DestinationPath $archive -ErrorAction Stop
        Write-Host "Share this log bundle: $archive"
    } catch { Write-Warning "Could not create ZIP; share the preserved folder $logDir" }
}
exit $exitCode
