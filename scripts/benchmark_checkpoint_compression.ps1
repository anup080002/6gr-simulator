[CmdletBinding()]
param(
    [string]$MatlabExe = 'C:\Program Files\MATLAB\R2026a\bin\matlab.exe',
    [Parameter(Mandatory=$true)][string]$OutputRoot
)
# Two sequential fresh MATLAB processes; never runs a scenario or testAll.
# Sampled phase peaks and OS process high-water marks are different metrics.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$target = [IO.Path]::GetFullPath($OutputRoot)
if (Test-Path -LiteralPath $target) { throw 'Use a new benchmark output folder; evidence is never overwritten.' }
if (Get-Process MATLAB -ErrorAction SilentlyContinue) {
    throw 'Finish/stop existing MATLAB work before the isolated memory benchmark.'
}
New-Item -ItemType Directory -Path $target | Out-Null
$allSamples = [Collections.Generic.List[object]]::new()
foreach ($compressed in @($true,$false)) {
    $token = if ($compressed) { 'true' } else { 'false' }
    $casePath = Join-Path $target $token
    New-Item -ItemType Directory -Path $casePath | Out-Null
    $matlabPath = $casePath.Replace("'","''")
    $code = "setup6GRSimToolkit('Verbose',false); testCheckpointCompressionBenchmark($token,'$matlabPath',true);"
    $args = @('-wait','-logfile',('"' + (Join-Path $casePath 'matlab.log') + '"'),'-batch',('"' + $code + '"'))
    $launcher = Start-Process -FilePath $MatlabExe -ArgumentList $args -WorkingDirectory $repo -WindowStyle Hidden -PassThru
    $phase = 'startup'
    do {
        $phaseFile = Join-Path $casePath 'benchmark_phase.json'
        if (Test-Path -LiteralPath $phaseFile) {
            try { $phase = (Get-Content -LiteralPath $phaseFile -Raw | ConvertFrom-Json).Phase } catch {}
        }
        # The -wait launcher is not the engine whose memory we are measuring.
        $engines = Get-CimInstance Win32_Process -Filter "Name='MATLAB.exe' AND ParentProcessId=$($launcher.Id)"
        foreach ($engine in $engines) {
            $p = Get-Process -Id $engine.ProcessId -ErrorAction SilentlyContinue
            if ($p) {
                $allSamples.Add([pscustomobject]@{
                    CompressionEnabled=$compressed; Phase=$phase; PID=$engine.ProcessId
                    UTC=[DateTime]::UtcNow.ToString('o')
                    PrivateBytes=$p.PrivateMemorySize64; WorkingSetBytes=$p.WorkingSet64
                    OSProcessPeakCommitBytes=([double]$engine.PeakPageFileUsage * 1024)
                    PeakScope='phase_sampled_private_bytes_and_process_lifetime_OS_commit_high_water'
                })
            }
        }
        Start-Sleep -Milliseconds 250
        $launcher.Refresh()
    } while (-not $launcher.HasExited)
    $launcher.WaitForExit()
    $allSamples | Export-Csv -LiteralPath (Join-Path $target 'memory_samples.csv') -NoTypeInformation
    if ($launcher.ExitCode -ne 0 -or -not (Test-Path -LiteralPath (Join-Path $casePath 'compression_benchmark.csv'))) {
        throw "Compression benchmark $token did not finish. Preserve its logs."
    }
}
$allSamples | Group-Object CompressionEnabled,Phase | ForEach-Object {
    $rows=$_.Group
    [pscustomobject]@{
        CompressionEnabled=$rows[0].CompressionEnabled; Phase=$rows[0].Phase; Samples=$rows.Count
        SampledPeakPrivateBytes=($rows | Measure-Object PrivateBytes -Maximum).Maximum
        SampledPeakWorkingSetBytes=($rows | Measure-Object WorkingSetBytes -Maximum).Maximum
        OSProcessPeakCommitBytes=($rows | Measure-Object OSProcessPeakCommitBytes -Maximum).Maximum
        Scope='sampled_phase_peak_not_exact_phase_peak; OS_counter_is_process_lifetime'
    }
} | Export-Csv -LiteralPath (Join-Path $target 'memory_peaks.csv') -NoTypeInformation
Write-Output "Completed isolated benchmark: $target"
