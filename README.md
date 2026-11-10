# Teams sound to ntfy

The ntfy topic is fixed as temochiz-lab1111222233334444. Subscribe to https://ntfy.sh/temochiz-lab1111222233334444 in ntfy.

## Start monitoring

Double-click start_notification_watcher.bat. The script samples audio sessions on the default Windows playback device and relays a short sound from ms-teams.exe or Teams.exe as Teams notification. Press Ctrl+C to stop.

No Graph API, PowerShell module, or extra application is required. The monitor uses Windows Core Audio APIs.

## Limits

This detects short Teams audio, not the notification itself. Teams must play a sound through a recognized Teams process on the default playback device. Silent notifications and sounds played through another process or device are not detected. Short sounds from calls or meetings may still trigger a relay. Longer continuous Teams audio is ignored.