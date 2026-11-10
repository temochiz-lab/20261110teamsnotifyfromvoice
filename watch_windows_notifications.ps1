param(
    [switch]$Stop,
    [switch]$Diagnose,
    [switch]$NoSend,
    [int]$DurationSeconds = 0,
    [double]$Threshold = 0.02
)

#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
if ($DurationSeconds -lt 0) { throw '-DurationSeconds must be 0 or greater.' }
if ($Threshold -lt 0.0001 -or $Threshold -gt 1.0) { throw '-Threshold must be between 0.0001 and 1.0.' }

$mutexName = 'Local\TeamsAudioRelayWatcher'
$eventName = 'Local\TeamsAudioRelayWatcherStop'
$mutex = $null
$stopEvent = $null
$ownsMutex = $false
$monitorStarted = $false
$stopRequested = $false
$noSendMode = $NoSend -or $Stop

function Read-RelaySettings([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Settings file not found: $Path" }
    $settings = @{}
    foreach ($line in Get-Content -LiteralPath $Path -Encoding UTF8) {
        $trimmed = $line.TrimStart()
        if (-not $trimmed -or $trimmed.StartsWith('#')) { continue }
        $parts = $line -split '=', 2
        if ($parts.Count -ne 2) { continue }
        $key = $parts[0].Trim()
        if ($key) { $settings[$key] = $parts[1].Trim() }
    }
    foreach ($key in @('topicname', 'pcname')) {
        if (-not $settings.ContainsKey($key) -or [string]::IsNullOrWhiteSpace($settings[$key])) { throw "Missing required setting: $key" }
    }
    return $settings
}

function Send-WatcherNotification([string]$Event) {
    if ($noSendMode) { return }
    $timestamp = [TimeZoneInfo]::ConvertTime([DateTimeOffset]::Now, [TimeZoneInfo]::FindSystemTimeZoneById('Tokyo Standard Time'))
    switch ($Event) {
        'Start' { $message = "Teams voice watcher Start [$($settings.pcname)]"; $priority = '3' }
        'Stop' { $message = "Teams voice watcher Stop [$($settings.pcname)] $($timestamp.ToString('yyyy-MM-dd HH:mm:ss zzz'))"; $priority = '3' }
        'Received' { $message = "Teams voice watcher Received from [$($settings.pcname)] $($timestamp.ToString('yyyy-MM-dd HH:mm:ss zzz'))"; $priority = '5' }
        default { throw "Unsupported notification event: $Event" }
    }
    $topicPath = [Uri]::EscapeDataString([string]$settings.topicname)
    try {
        Invoke-RestMethod -Uri "https://ntfy.sh/$topicPath" -Method Post -Headers @{ Priority = $priority } -ContentType 'text/plain; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($message)) -TimeoutSec 15 | Out-Null
        Write-Host "ntfy $Event notification sent to topic $($settings.topicname)."
    } catch { Write-Warning "Could not send ntfy $Event notification to topic $($settings.topicname): $($_.Exception.Message)" }
}

function Get-TeamsProcessIds {
    $all = @(Get-CimInstance Win32_Process -ErrorAction Stop | Select-Object ProcessId, ParentProcessId, Name)
    $ids = [Collections.Generic.HashSet[uint32]]::new()
    foreach ($process in $all) {
        if ($process.Name -ieq 'ms-teams.exe' -or $process.Name -ieq 'teams.exe') { [void]$ids.Add([uint32]$process.ProcessId) }
    }
    do {
        $added = $false
        foreach ($process in $all) {
            if ($ids.Contains([uint32]$process.ParentProcessId) -and $ids.Add([uint32]$process.ProcessId)) { $added = $true }
        }
    } while ($added)
    return ,([uint32[]]@($ids))
}

if ($Stop) {
    $settings = Read-RelaySettings (Join-Path $PSScriptRoot 'setting.txt')
    if ($NoSend) { Write-Host 'Stop mode suppresses ntfy sending.' }
    try { $stopEvent = [Threading.EventWaitHandle]::OpenExisting($eventName) }
    catch [Threading.WaitHandleCannotBeOpenedException] { Write-Host 'No active watcher stop event; watcher is already stopped.'; Send-WatcherNotification 'Stop'; exit 0 }
    try {
        $stopEvent.Set() | Out-Null
        try { $mutex = [Threading.Mutex]::OpenExisting($mutexName) }
        catch [Threading.WaitHandleCannotBeOpenedException] { Write-Host 'Watcher stop request completed.'; Send-WatcherNotification 'Stop'; exit 0 }
        try {
            try { $ownsMutex = $mutex.WaitOne(25000) } catch [Threading.AbandonedMutexException] { $ownsMutex = $true }
            if ($ownsMutex) { Write-Host 'Watcher stop request completed.'; Send-WatcherNotification 'Stop' }
            else { Write-Warning 'Timed out waiting for watcher to stop.' }
        } finally { if ($ownsMutex) { $mutex.ReleaseMutex(); $ownsMutex = $false }; if ($mutex) { $mutex.Dispose() } }
    } finally { $stopEvent.Dispose() }
    exit 0
}

try {
    $settings = Read-RelaySettings (Join-Path $PSScriptRoot 'setting.txt')
    $topicUri = "https://ntfy.sh/$([Uri]::EscapeDataString([string]$settings.topicname))"
    $mutex = [Threading.Mutex]::new($false, $mutexName)
    try { $ownsMutex = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $ownsMutex = $true }
    if (-not $ownsMutex) { Write-Host 'Watcher is already running.'; exit 0 }
    $createdNewEvent = $false
    $stopEvent = [Threading.EventWaitHandle]::new($false, [Threading.EventResetMode]::ManualReset, $eventName, [ref]$createdNewEvent)
    if (-not $createdNewEvent) { throw 'A stop event already exists while the watcher mutex is available.' }

    Add-Type -Path (Join-Path $PSScriptRoot 'AudioSessionMeter.cs')
    [void][TeamsAudioRelay.AudioSessions]::ReadAllRenderSessions()
    $teamsProcessIds = [uint32[]]@()
    $lastProcessRefreshAt = [DateTime]::MinValue
    $audioActive = $false
    $audioStartedAt = [DateTime]::MinValue
    $lastAudioAt = [DateTime]::MinValue
    $diagnosticPeak = 0.0
    $lastDiagnosticAt = [DateTime]::MinValue
    $watchStartedAt = Get-Date
    Write-Host "Monitoring Teams audio on all active playback devices. ntfy topic: $($settings.topicname)"
    Write-Host "Teams process tree and children are included. Script: $PSCommandPath"
    if ($noSendMode) { Write-Host 'Sending disabled (-NoSend).' }
    $monitorStarted = $true
    Send-WatcherNotification 'Start'

    while ($true) {
        try {
            if ($stopEvent.WaitOne(0)) { $stopRequested = $true; break }
            $now = Get-Date
            if ($teamsProcessIds.Count -eq 0 -or ($now - $lastProcessRefreshAt).TotalSeconds -ge 2) {
                $teamsProcessIds = Get-TeamsProcessIds
                $lastProcessRefreshAt = $now
            }
            $teamsPeak = 0.0
            $teamsSessionCount = 0
            foreach ($sample in [TeamsAudioRelay.AudioSessions]::ReadAllRenderSessions()) {
                if ($sample.ProcessId -ne 0 -and $teamsProcessIds -contains [uint32]$sample.ProcessId) {
                    $teamsSessionCount++
                    if ($sample.Peak -gt $teamsPeak) { $teamsPeak = $sample.Peak }
                }
            }
            if ($teamsPeak -gt $diagnosticPeak) { $diagnosticPeak = $teamsPeak }
            if ($Diagnose -and (($now - $lastDiagnosticAt).TotalSeconds -ge 5)) {
                Write-Host ("[{0}] Teams peak={1:F4}, sessions={2}" -f $now.ToString('HH:mm:ss'), $diagnosticPeak, $teamsSessionCount)
                $diagnosticPeak = 0.0
                $lastDiagnosticAt = $now
            }
            if ($teamsPeak -ge $Threshold) {
                if (-not $audioActive) { $audioActive = $true; $audioStartedAt = $now }
                $lastAudioAt = $now
            } elseif ($audioActive -and ($now - $lastAudioAt).TotalMilliseconds -ge 500) {
                $soundDuration = ($lastAudioAt - $audioStartedAt).TotalMilliseconds
                if ($soundDuration -le 1800) { Send-WatcherNotification 'Received' }
                $audioActive = $false
            }
            if ($DurationSeconds -gt 0 -and ($now - $watchStartedAt).TotalSeconds -ge $DurationSeconds) { break }
            Start-Sleep -Milliseconds 100
        } catch {
            Write-Warning "Audio monitoring error: $($_.Exception.Message)"
            Start-Sleep -Seconds 2
        }
    }
} finally {
    $eventIsSet = $false
    if ($stopEvent) { $eventIsSet = $stopEvent.WaitOne(0) }
    if ($monitorStarted -and -not $stopRequested -and -not $eventIsSet) { Send-WatcherNotification 'Stop' }
    if ($stopEvent) { $stopEvent.Dispose() }
    if ($ownsMutex -and $mutex) { $mutex.ReleaseMutex() }
    if ($mutex) { $mutex.Dispose() }
}




