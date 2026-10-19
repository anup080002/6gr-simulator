[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$RunFolder,
    [Parameter(Mandatory=$true)][string]$ArchiveFolder,
    [switch]$PlanOnly
)

# Storage relocation only. No MATLAB source, receiver, CSV value, MAT byte or
# scientific identity is modified. The existing channel/mat pathname remains
# the public owner through a Windows directory junction.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Get-ExactDirectory([string]$PathValue) {
    $resolved = [System.IO.Path]::GetFullPath($PathValue).TrimEnd('\')
    if ($resolved -eq [System.IO.Path]::GetPathRoot($resolved).TrimEnd('\')) {
        throw 'An archive operation may not target a drive root.'
    }
    return $resolved
}

function Assert-Within([string]$Child, [string]$Parent) {
    if (-not $Child.StartsWith($Parent.TrimEnd('\') + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Path escapes the explicitly selected storage directory: $Child"
    }
}

function Get-SHA256([string]$PathValue) {
    return (Get-FileHash -LiteralPath $PathValue -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Assert-RunStopped([string]$SelectedRun, [string]$SelectedLeaf) {
    $active = @(Get-CimInstance Win32_Process -Filter "Name='MATLAB.exe'" | Where-Object {
        $_.CommandLine -and ($_.CommandLine.Contains($SelectedRun) -or $_.CommandLine.Contains($SelectedLeaf))
    })
    if ($active.Count -gt 0) {
        throw "Selected run still has a MATLAB process: $($active.ProcessId -join ','). Stop it at its verified checkpoint first."
    }
}

$runPath = Get-ExactDirectory $RunFolder
$archivePath = Get-ExactDirectory $ArchiveFolder
$logicalPath = Get-ExactDirectory (Join-Path $runPath 'channel\mat')
$metadataPath = Get-ExactDirectory (Join-Path $runPath 'meta')
Assert-Within $logicalPath $runPath
Assert-Within $metadataPath $runPath
if (-not (Test-Path -LiteralPath (Join-Path $metadataPath 'scenario_config_identity.json') -PathType Leaf)) {
    throw 'An existing run identity is required; this command does not create or execute a scenario.'
}
if ($archivePath.StartsWith($runPath + '\', [System.StringComparison]::OrdinalIgnoreCase) -or
    $runPath.StartsWith($archivePath + '\', [System.StringComparison]::OrdinalIgnoreCase) -or
    $runPath -eq $archivePath) {
    throw 'The external archive and selected run must be disjoint directories.'
}
$runLeaf = Split-Path -Leaf $runPath
Assert-RunStopped $runPath $runLeaf
$logicalItem = Get-Item -LiteralPath $logicalPath
if (-not $logicalItem.PSIsContainer -or ($logicalItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
    throw 'The source must be an ordinary, existing channel/mat directory; inspect prior relocation before repeating.'
}
if (Test-Path -LiteralPath $archivePath) {
    throw 'Archive destination already exists. Preserve it and choose a new exact destination.'
}
$files = @(Get-ChildItem -LiteralPath $logicalPath -Force)
if ($files.Count -eq 0 -or @($files | Where-Object {
    $_.PSIsContainer -or $_.Extension -ine '.mat' -or
    ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $_.Name -like 'm_*'
}).Count -gt 0) {
    throw 'Only completed MAT archives are supported; preserve and inspect empty, temporary, nested or linked entries.'
}
$bytes = [long](($files | Measure-Object Length -Sum).Sum)
$archiveDrive = [System.IO.DriveInfo]::new([System.IO.Path]::GetPathRoot($archivePath))
if ($archiveDrive.AvailableFreeSpace -lt $bytes + 1GB) {
    throw "Insufficient destination reserve: archive bytes=$bytes free=$($archiveDrive.AvailableFreeSpace)."
}
if ($PlanOnly) {
    [pscustomobject]@{ Status='plan_only_no_files_changed'; RunFolder=$runPath;
        LogicalFolder=$logicalPath; ArchiveFolder=$archivePath;
        FileCount=$files.Count; Bytes=$bytes; DestinationFreeBytes=$archiveDrive.AvailableFreeSpace } | ConvertTo-Json
    return
}
$receiptPath = Join-Path $metadataPath 'channel_archive_storage.json'
if (Test-Path -LiteralPath $receiptPath) { throw 'A storage receipt already exists; do not overwrite its ownership.' }
$records = @($files | ForEach-Object {
    [pscustomobject]@{Name=$_.Name; Bytes=[long]$_.Length; SHA256=(Get-SHA256 $_.FullName)}
})
New-Item -ItemType Directory -Path $archivePath | Out-Null
foreach ($record in $records) {
    $sourceFile = Join-Path $logicalPath $record.Name
    $destinationFile = Join-Path $archivePath $record.Name
    Assert-Within $sourceFile $logicalPath
    Assert-Within $destinationFile $archivePath
    Copy-Item -LiteralPath $sourceFile -Destination $destinationFile
    if ((Get-Item -LiteralPath $destinationFile).Length -ne $record.Bytes -or
        (Get-SHA256 $destinationFile) -ne $record.SHA256 -or
        (Get-SHA256 $sourceFile) -ne $record.SHA256) {
        throw 'Copy/source checksum mismatch; original files retained. Do not resume until inspected.'
    }
}
# Rename is recoverable, and the final absolute backup stays inside this
# exact run's channel directory. Never enumerate into a different shell.
$backupPath = Get-ExactDirectory (Join-Path (Split-Path -Parent $logicalPath) ('mat_relocation_backup_' + [guid]::NewGuid()))
Assert-Within $backupPath (Get-ExactDirectory (Join-Path $runPath 'channel'))
Assert-RunStopped $runPath $runLeaf
$currentFiles = @(Get-ChildItem -LiteralPath $logicalPath -Force)
if ($currentFiles.Count -ne $records.Count -or
    @(Compare-Object @($currentFiles.Name | Sort-Object) @($records.Name | Sort-Object)).Count -gt 0) {
    throw 'Source archive inventory changed during copy; originals retained and no junction installed.'
}
Move-Item -LiteralPath $logicalPath -Destination $backupPath
try {
    New-Item -ItemType Junction -Path $logicalPath -Target $archivePath | Out-Null
    foreach ($record in $records) {
        $visibleFile = Join-Path $logicalPath $record.Name
        if ((Get-Item -LiteralPath $visibleFile).Length -ne $record.Bytes -or
            (Get-SHA256 $visibleFile) -ne $record.SHA256) {
            throw 'The original public archive path did not reproduce the exact bytes.'
        }
    }
} catch {
    # Preserve both the verified copy and the original backup on any failure.
    throw "Relocation incomplete; originals preserved at $backupPath. $($_.Exception.Message)"
}
$receipt = [ordered]@{ Contract='LLSExternalChannelArchive/v1'; Status='verified';
    RunFolder=$runPath; LogicalRelativeFolder='channel/mat'; ExternalFolder=$archivePath;
    FileCount=$records.Count; Bytes=$bytes; Files=$records;
    ScientificDataChanged=$false; SourceCodeMoved=$false;
    CreatedUTC=[DateTime]::UtcNow.ToString('o'); UtilitySHA256=(Get-SHA256 $PSCommandPath) }
[IO.File]::WriteAllText($receiptPath, ($receipt | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))
# Delete only the individually verified originals, after the visible junction
# and independent destination passed checks. The evidence remains recoverable
# at both its original logical pathname and the recorded external directory.
foreach ($record in $records) {
    $backupFile = Join-Path $backupPath $record.Name
    Assert-Within $backupFile $backupPath
    if ((Get-SHA256 $backupFile) -ne $record.SHA256) {
        throw 'Original changed after copy. Preserve the remaining backup for inspection.'
    }
    Remove-Item -LiteralPath $backupFile
}
if (@(Get-ChildItem -LiteralPath $backupPath -Force).Count -eq 0) {
    Remove-Item -LiteralPath $backupPath
}
$receipt | ConvertTo-Json -Depth 5
