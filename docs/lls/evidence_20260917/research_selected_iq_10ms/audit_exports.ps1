param([Parameter(Mandatory=$true)][string]$RunFolder)
$ErrorActionPreference = 'Stop'
$packageRoot = (Resolve-Path -LiteralPath $RunFolder).Path
$manifestPath = Join-Path $packageRoot 'meta/manifest.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if ($manifest.Status -ne 'completed' -or -not $manifest.ResultOk -or $manifest.GitDirty) { throw 'Package is not a completed passing clean-source capture.' }
$iq = @(Import-Csv -LiteralPath (Join-Path $packageRoot 'waveform/iq_manifest.csv'))
$timeline = @(Import-Csv -LiteralPath (Join-Path $packageRoot 'air_interface/csv/timeline.csv'))
$trials = @(Import-Csv -LiteralPath (Join-Path $packageRoot 'reports/csv/trials.csv'))
$summaries = @(Import-Csv -LiteralPath (Join-Path $packageRoot 'reports/csv/summary.csv'))
if ($iq.Count -ne 8 -or $timeline.Count -ne 80 -or $trials.Count -ne 70) { throw 'Unexpected selected-point population.' }
if (@($iq | ForEach-Object { $_.Direction + '_' + $_.CapturePoint + '_' + $_.Port } | Sort-Object -Unique).Count -ne 8) { throw 'Duplicate IQ stream identity.' }
if ($summaries.Count -ne 2 -or @($summaries.Direction | Sort-Object -Unique).Count -ne 2) { throw 'Direction summary population mismatch.' }
if (@($trials.TBID | Sort-Object -Unique).Count -ne $trials.Count) { throw 'Duplicate TB identity.' }
$cursor = 0L
$slot = 0
foreach ($tick in $timeline) {
    if ([int]$tick.AbsoluteSlot -ne $slot) { throw 'Absolute slot ordering mismatch.' }
    $expectedDL = [int](($slot % 8) -in @(0,1,2)); $expectedUL = [int](($slot % 8) -in @(4,5,6,7))
    if ([int]$tick.DLActive -ne $expectedDL -or [int]$tick.ULActive -ne $expectedUL) { throw 'Selected TDD allocation mismatch.' }
    if ([long]$tick.StartSample -ne $cursor -or [long]$tick.StopSampleExclusive -le $cursor) { throw 'Clock gap or overlap.' }
    if ($tick.DLActive -eq '1' -and $tick.ULActive -eq '1') { throw 'TDD direction overlap.' }
    $cursor = [long]$tick.StopSampleExclusive
    $slot++
}
if ($cursor -ne 4915200 -or $cursor -ne $manifest.SampleCount) { throw 'Wrong capture extent.' }
$horizon = $cursor / [double]$manifest.SampleRateHz
if ([math]::Abs($horizon - .01) -gt 1e-12) { throw 'Wrong full-clock horizon.' }
Add-Type -TypeDefinition @'
using System;
using System.IO;
public static class ResearchIQReadOnlyAudit {
    public static bool HasNonzero(string path, long start, long count) {
        using (var stream = File.OpenRead(path)) {
            stream.Seek(start, SeekOrigin.Begin);
            byte[] buffer = new byte[65536];
            while (count > 0) {
                int got = stream.Read(buffer, 0, (int)Math.Min(count, buffer.Length));
                if (got == 0) throw new EndOfStreamException();
                for (int i = 0; i < got; i++) if (buffer[i] != 0) return true;
                count -= got;
            }
            return false;
        }
    }
}
'@
$hashes = @{}
$silentSamples = 0L
$noisyIntervals = 0
$level5VSAFiles = 0
foreach ($stream in $iq) {
    if ($stream.Direction -notin @('DL','UL') -or [int]$stream.Port -notin @(1,2)) { throw 'Unexpected endpoint or port.' }
    if ([long]$stream.SampleCount -ne $cursor -or [double]$stream.SampleRateHz -ne 491520000 -or [double]$stream.CenterFrequencyHz -ne 7000000000) { throw 'IQ metadata mismatch.' }
    if ($stream.StandardNR -ne '0' -or $stream.InstrumentImportVerified -ne '0' -or [int]$stream.ClippedComponents -ne 0) { throw 'Incorrect qualification or clipping claim.' }
    if ([double]$stream.QuantizationMaxError -gt .5/32767 + 1e-15) { throw 'Quantization bound exceeded.' }
    foreach ($pair in @(@('RawMAT','RawSHA256'),@('WIQFile','WIQSHA256'),@('VSAMATFile','VSAMATSHA256'))) {
        $artifactPath = (Resolve-Path -LiteralPath $stream.($pair[0])).Path
        if (-not $artifactPath.StartsWith($packageRoot + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw 'Artifact is outside package.' }
        if (-not $hashes.ContainsKey($artifactPath)) { $hashes[$artifactPath] = (Get-FileHash -LiteralPath $artifactPath -Algorithm SHA256).Hash }
        if ($hashes[$artifactPath] -ne $stream.($pair[1])) { throw "Hash mismatch: $artifactPath" }
    }
    if ((Get-Item -LiteralPath $stream.WIQFile).Length -ne $cursor * 4) { throw 'WIQ byte/sample mismatch.' }
    $headerStream = [IO.File]::OpenRead($stream.VSAMATFile)
    try {
        $header = New-Object byte[] 128
        if ($headerStream.Read($header,0,128) -ne 128 -or -not [Text.Encoding]::ASCII.GetString($header).StartsWith('MATLAB 5.0 MAT-file')) { throw 'Unexpected VSA MAT container header.' }
        $level5VSAFiles++
    } finally { $headerStream.Dispose() }
    foreach ($tick in $timeline) {
        if ($tick.($stream.Direction + 'Active') -ne '0') { continue }
        $count = [long]$tick.StopSampleExclusive - [long]$tick.StartSample
        $nonzero = [ResearchIQReadOnlyAudit]::HasNonzero($stream.WIQFile,[long]$tick.StartSample*4,$count*4)
        if ($stream.CapturePoint -eq 'TX') {
            if ($nonzero) { throw 'Nonzero transmitter samples in an inactive TDD interval.' }
            $silentSamples += $count
        } elseif ($stream.CapturePoint -eq 'RX') {
            if (-not $nonzero) { throw 'Inactive RX interval incorrectly lacks configured noise.' }
            $noisyIntervals++
        } else { throw 'Unknown capture point.' }
    }
}
if ($hashes.Count -ne 20) { throw 'Unexpected raw/playback artifact population.' }
foreach ($trial in $trials) {
    if ($trial.CRCPass -ne '1' -or $trial.TBExact -ne '1' -or [int]$trial.BitErrors -ne 0 -or [int]$trial.Qm -ne 10 -or [int]$trial.Layers -ne 2) { throw 'Selected-point PHY result mismatch.' }
    $snr = 10*[math]::Log10([double]$trial.ExpectedDataREPowerPerPort/[double]$trial.ExpectedGridNoiseVariance)
    if ([int]$trial.TBSBits -ne 622760 -or [double]$trial.ExpectedDataREPowerPerPort -ne .5 -or [double]$trial.ExpectedGridNoiseVariance -ne .0005) { throw 'Selected-point allocation or energy mismatch.' }
    $evmSinr = -20*[math]::Log10([double]$trial.EVMRMS)
    if ([math]::Abs($snr-30) -gt 1e-10 -or [math]::Abs($evmSinr-[double]$trial.ReferenceErrorSINRdB) -gt 1e-10) { throw 'Noise or EVM/SINR accounting mismatch.' }
}
$goodput = @{}
foreach ($summary in $summaries) {
    $rows = @($trials | Where-Object Direction -eq $summary.Direction)
    $bits = ($rows | ForEach-Object {[long]$_.TBSBits} | Measure-Object -Sum).Sum
    if ($bits -ne [long]$summary.DeliveredUniqueBits -or [math]::Abs($bits/$horizon-[double]$summary.GoodputBitsPerSecond) -gt .001) { throw 'Summary disagrees with actual unique TB bits/full clock.' }
    $goodput[$summary.Direction] = $bits/$horizon
}
[ordered]@{
    AuditMethod='independent_PowerShell_read_only_export_reconciliation'; SourceCommit=$manifest.GitCommit
    ManifestSHA256=(Get-FileHash -LiteralPath $manifestPath).Hash; Package=$packageRoot
    UniqueArtifactHashesVerified=$hashes.Count; WIQStreams=$iq.Count; SamplesPerStream=$cursor; Level5VSAMATHeadersVerified=$level5VSAFiles
    ContiguousTDDSlots=$timeline.Count; UniqueTBs=$trials.Count; HorizonSeconds=$horizon
    DLGoodputBitsPerSecond=$goodput.DL; ULGoodputBitsPerSecond=$goodput.UL
    InactiveTXComplexSamplesVerifiedZero=$silentSamples; InactiveRXIntervalsWithNoise=$noisyIntervals
    NoiseBudgetAndEVMConversionReconciled=$true; IQRegenerated=$false
    PHYDecodingReexecutedByAudit=$false; KeysightImportVerified=$false
} | ConvertTo-Json -Depth 4
