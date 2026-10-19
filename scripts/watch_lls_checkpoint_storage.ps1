[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$RunFolder,
    [Parameter(Mandatory=$true)][int]$MatlabProcessId,
    [Parameter(Mandatory=$true)][string]$ExpectedCommandToken,
    [int]$AfterCompletedSlot = 45,
    [double]$ArchiveReserveGiB = 24,
    [double]$RunReserveGiB = 30,
    [switch]$InspectOnly
)
# User-authorized storage safety stop, not a PHY or acceptance override.
# Only stop the exact selected MATLAB process after a NEW committed checkpoint.
# Keep the source, physical evidence and checkpoint bytes untouched.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$runPath = [IO.Path]::GetFullPath($RunFolder).TrimEnd('\')
if ($runPath -eq [IO.Path]::GetPathRoot($runPath).TrimEnd('\') -or
    $ExpectedCommandToken.Length -lt 8 -or $ArchiveReserveGiB -le 0 -or $RunReserveGiB -le 0) {
    throw 'An exact run directory, specific process token and positive storage reserves are required.'
}
$selected = Get-CimInstance Win32_Process -Filter "ProcessId=$MatlabProcessId"
if (-not $selected -or $selected.Name -ine 'MATLAB.exe' -or
    -not $selected.CommandLine.Contains($ExpectedCommandToken)) {
    throw 'The selected PID is not the declared MATLAB run.'
}
$creationTime = $selected.CreationDate
$checkpointRoot = [IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $runPath) ('.checkpoints\' + (Split-Path -Leaf $runPath))))
$latestPath = Join-Path $runPath 'meta\latest_slot_checkpoint.json'
while ($true) {
    $current = Get-CimInstance Win32_Process -Filter "ProcessId=$MatlabProcessId"
    if (-not $current) { Write-Output 'Selected MATLAB process exited; no stop performed.'; break }
    if ($current.CreationDate -ne $creationTime -or $current.Name -ine 'MATLAB.exe' -or
        -not $current.CommandLine.Contains($ExpectedCommandToken)) {
        throw 'Process identity changed; no stop performed.'
    }
    $record = $null
    if (Test-Path -LiteralPath $latestPath -PathType Leaf) {
        try { $record = Get-Content -LiteralPath $latestPath -Raw | ConvertFrom-Json } catch {
            if ($InspectOnly) { throw }
        }
    }
    $archivePath = Join-Path $runPath 'channel\mat'
    $storageReceipt = Join-Path $runPath 'meta\channel_archive_storage.json'
    if (Test-Path -LiteralPath $storageReceipt -PathType Leaf) {
        $storage = Get-Content -LiteralPath $storageReceipt -Raw | ConvertFrom-Json
        if ($storage.Contract -ne 'LLSExternalChannelArchive/v1' -or $storage.Status -ne 'verified' -or
            [IO.Path]::GetFullPath($storage.RunFolder).TrimEnd('\') -ine $runPath) {
            throw 'External storage receipt does not identify this run.'
        }
        $archivePath = [IO.Path]::GetFullPath($storage.ExternalFolder)
    }
    $runFree = [IO.DriveInfo]::new([IO.Path]::GetPathRoot($runPath)).AvailableFreeSpace
    $archiveFree = [IO.DriveInfo]::new([IO.Path]::GetPathRoot($archivePath)).AvailableFreeSpace
    $tight = $runFree -lt $RunReserveGiB * 1GB -or $archiveFree -lt $ArchiveReserveGiB * 1GB
    if ($InspectOnly) {
        [pscustomobject]@{ProcessId=$MatlabProcessId; RunFreeGiB=$runFree/1GB;
            ArchiveFreeGiB=$archiveFree/1GB; StorageTight=$tight;
            Checkpoint=$record; Action='inspect_only_no_stop'} | ConvertTo-Json -Depth 4
        break
    }
    if ($record -and [int]$record.CompletedSlotOneBased -gt $AfterCompletedSlot) {
        if ($tight) {
            $statePath = [IO.Path]::GetFullPath([string]$record.Checkpoint)
            if (-not $statePath.StartsWith($checkpointRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
                throw 'Checkpoint leaves the selected run checkpoint tree; no stop performed.'
            }
            $receiptPath = Join-Path (Split-Path -Parent $statePath) 'checkpoint.json'
            $receipt = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
            if ($receipt.Status -ne 'complete' -or
                [int]$receipt.CompletedSlotOneBased -ne [int]$record.CompletedSlotOneBased -or
                [IO.Path]::GetFullPath($receipt.RunFolder).TrimEnd('\') -ine $runPath -or
                (Get-FileHash -LiteralPath $statePath -Algorithm SHA256).Hash -ine $receipt.StateSHA256) {
                throw 'Committed checkpoint identity/hash did not verify; no stop performed.'
            }
            $current = Get-CimInstance Win32_Process -Filter "ProcessId=$MatlabProcessId"
            if (-not $current) { break }
            if ($current.CreationDate -ne $creationTime -or -not $current.CommandLine.Contains($ExpectedCommandToken)) {
                throw 'Process identity changed during verification; no stop performed.'
            }
            Stop-Process -Id $MatlabProcessId -ErrorAction Stop
            [pscustomobject]@{Status='stopped_after_verified_checkpoint_storage_reserve';
                ProcessId=$MatlabProcessId; CompletedSlot=$receipt.CompletedSlotOneBased;
                NextSlot=$receipt.NextSlotOneBased; Checkpoint=$statePath;
                StateSHA256=$receipt.StateSHA256; RunFreeGiB=$runFree/1GB;
                ArchiveFreeGiB=$archiveFree/1GB; EvidenceDeleted=$false;
                UTC=[DateTime]::UtcNow.ToString('o')} | ConvertTo-Json
            break
        }
        $AfterCompletedSlot = [int]$record.CompletedSlotOneBased
    }
    Start-Sleep -Seconds 5
}
