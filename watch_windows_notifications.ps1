#Requires -Version 5.1
Add-Type -Path (Join-Path $PSScriptRoot 'AudioSessionMeter.cs')
$topic='temochiz-lab1111222233334444'
$uri="https://ntfy.sh/$topic"
$threshold=0.02
$silenceToRearmMs=500
$maxNotificationSoundMs=1800
$teamsProcessNames=@('ms-teams','teams')
try { [void][TeamsAudioRelay.AudioSessions]::ReadDefaultRenderSessions() }
catch { throw "Cannot access the default playback device. Run this batch in the signed-in Windows desktop session. $($_.Exception.Message)" }
$audioActive=$false
$audioStartedAt=[DateTime]::MinValue
$lastAudioAt=[DateTime]::MinValue
Write-Host "Monitoring short Teams sounds on the default playback device. ntfy topic: $topic"
Write-Host 'A short sound from Teams sends one ntfy message. Press Ctrl+C to stop.'
Write-Host 'Longer Teams audio, such as calls, is ignored.'
while($true){
 try {
  $teamsPeak=0.0
  foreach($sample in [TeamsAudioRelay.AudioSessions]::ReadDefaultRenderSessions()){
   $process=Get-Process -Id $sample.ProcessId -ErrorAction SilentlyContinue
   if($process -and $teamsProcessNames -contains $process.ProcessName.ToLowerInvariant()){
    if($sample.Peak -gt $teamsPeak){$teamsPeak=$sample.Peak}
   }
  }
  $now=Get-Date
  if($teamsPeak -ge $threshold){
   if(-not $audioActive){$audioActive=$true;$audioStartedAt=$now}
   $lastAudioAt=$now
  }elseif($audioActive -and ($now-$lastAudioAt).TotalMilliseconds -ge $silenceToRearmMs){
   $soundDuration=($lastAudioAt-$audioStartedAt).TotalMilliseconds
   if($soundDuration -le $maxNotificationSoundMs){
    try{
     Invoke-RestMethod -Uri $uri -Method Post -ContentType 'text/plain; charset=utf-8' -Body ([System.Text.Encoding]::UTF8.GetBytes('Teams notification')) -TimeoutSec 15|Out-Null
     Write-Host "[$($now.ToString('HH:mm:ss'))] Relayed a short Teams sound to ntfy."
    }catch{Write-Warning "Could not send to ntfy: $($_.Exception.Message)"}
   }
   $audioActive=$false
  }
 }catch{Write-Warning "Audio monitoring error: $($_.Exception.Message)";Start-Sleep -Seconds 2}
 Start-Sleep -Milliseconds 100
}