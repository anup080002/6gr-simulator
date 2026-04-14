param(
    [string]$BaseUrl = "http://127.0.0.1:62906",
    [string]$Scenario = "lls_3gpp_rel20_anchor_4ghz_100mhz_waveform_honest_200ue_4000slot.yaml",
    [string]$Username = "admin",
    [string]$Password = "admin",
    [string]$RunTag = "",
    [int]$MaxAttempts = 10
)

if ([string]::IsNullOrWhiteSpace($RunTag)) {
    $RunTag = "webgui_rel20_4ghz_100mhz_200ue_4000slot_" + (Get-Date -Format "yyyyMMdd_HHmmss")
}

$session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
$loginBody = @{
    username = $Username
    password = $Password
    next = "/home"
}
Invoke-WebRequest -Uri ($BaseUrl.TrimEnd('/') + "/login") -Method Post -Body $loginBody -WebSession $session -MaximumRedirection 5 | Out-Null

$runBody = @{
    scenario = $Scenario
    execution_mode = "LLS"
    run_tag = $RunTag
}

Invoke-WebRequest -Uri ($BaseUrl.TrimEnd('/') + "/run") -Method Post -Body $runBody -WebSession $session -MaximumRedirection 0 -ErrorAction SilentlyContinue | Out-Null
Write-Host "Submitted /run for scenario $Scenario with run_tag $RunTag"
Write-Host "Use monitor_lls_run.ps1 against $BaseUrl and run tag $RunTag"
