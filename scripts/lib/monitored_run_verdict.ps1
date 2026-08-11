function ConvertTo-SixGRBoolean {
    param([object]$Value)
    if ($Value -is [bool]) {
        return [bool]$Value
    }
    return ([string]$Value).Trim().ToLowerInvariant() -in @("1", "true", "yes", "pass")
}

function Test-SixGRFiniteDouble {
    param([double]$Value)
    return -not [double]::IsNaN($Value) -and -not [double]::IsInfinity($Value)
}

function Get-SixGRLastMarkerValue {
    param(
        [string]$Text,
        [string]$Marker
    )
    $pattern = "(?m)^" + [regex]::Escape($Marker) + "=([^\r\n]+)\s*$"
    $matches = [regex]::Matches($Text, $pattern)
    if ($matches.Count -eq 0) {
        return $null
    }
    return $matches[$matches.Count - 1].Groups[1].Value.Trim()
}

function Get-SixGRMonitoredTerminalVerdict {
    param(
        [Parameter(Mandatory = $true)][string]$MatlabLog,
        [Parameter(Mandatory = $true)][string]$RunFolder
    )

    $reasons = [System.Collections.Generic.List[string]]::new()
    $logText = ""
    if (Test-Path -LiteralPath $MatlabLog) {
        $logText = Get-Content -LiteralPath $MatlabLog -Raw
    } else {
        $reasons.Add("matlab_log_missing")
    }

    $markerOk = ConvertTo-SixGRBoolean (Get-SixGRLastMarkerValue -Text $logText -Marker "CodexMonitoredOk")
    $markerResultOk = ConvertTo-SixGRBoolean (Get-SixGRLastMarkerValue -Text $logText -Marker "CodexMonitoredResultOk")
    $markerCompletion = [string](Get-SixGRLastMarkerValue -Text $logText -Marker "CodexMonitoredRunCompletion")
    $markerFailureRaw = Get-SixGRLastMarkerValue -Text $logText -Marker "CodexMonitoredRequiredFailureCount"
    $markerFailureCount = [double]::NaN
    if ($null -ne $markerFailureRaw) {
        [double]::TryParse([string]$markerFailureRaw, [ref]$markerFailureCount) | Out-Null
    }
    $markersPass = $markerOk -and $markerResultOk -and $markerCompletion -eq "completed" -and `
        (Test-SixGRFiniteDouble $markerFailureCount) -and $markerFailureCount -eq 0
    if (-not $markersPass) {
        $reasons.Add("terminal_matlab_markers_not_successful")
    }

    $summaryPath = Join-Path $RunFolder "reports\csv\scenario_summary.csv"
    $summaryPass = $false
    $summaryResultOk = $false
    $summaryCompletion = ""
    $summaryFailureCount = [double]::NaN
    if (Test-Path -LiteralPath $summaryPath) {
        try {
            $rows = @(Import-Csv -LiteralPath $summaryPath)
            if ($rows.Count -gt 0) {
                $row = $rows[$rows.Count - 1]
                $summaryResultOk = ConvertTo-SixGRBoolean $row.ResultOk
                $summaryCompletion = [string]$row.RunCompletion
                [double]::TryParse([string]$row.RequiredFailureCount, [ref]$summaryFailureCount) | Out-Null
                $summaryPass = $summaryResultOk -and $summaryCompletion -eq "completed" -and `
                    (Test-SixGRFiniteDouble $summaryFailureCount) -and $summaryFailureCount -eq 0
            }
        } catch {
            $reasons.Add("scenario_summary_unreadable")
        }
    } else {
        $reasons.Add("scenario_summary_missing")
    }
    if (-not $summaryPass) {
        $reasons.Add("scenario_summary_not_successful")
    }

    [pscustomobject]@{
        Ok = [bool]($markersPass -and $summaryPass)
        MarkerOk = [bool]$markerOk
        MarkerResultOk = [bool]$markerResultOk
        MarkerRunCompletion = $markerCompletion
        MarkerRequiredFailureCount = $markerFailureCount
        SummaryResultOk = [bool]$summaryResultOk
        SummaryRunCompletion = $summaryCompletion
        SummaryRequiredFailureCount = $summaryFailureCount
        FailureReasons = [string]::Join(";", $reasons)
        SummaryPath = $summaryPath
    }
}
