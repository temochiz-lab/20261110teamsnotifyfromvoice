#Requires -Version 5.1
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$icon = [System.Windows.Forms.NotifyIcon]::new()
try {
    $icon.Icon = [System.Drawing.SystemIcons]::Information
    $icon.Visible = $true
    $icon.BalloonTipTitle = 'ntfy'
    $icon.BalloonTipText = 'Notified'
    $icon.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Info
    $icon.ShowBalloonTip(5000)
    Start-Sleep -Seconds 6
}
finally {
    $icon.Visible = $false
    $icon.Dispose()
}