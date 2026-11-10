# Teams audio notification relay

This PowerShell 5.1 utility watches audio sessions from Teams and its child processes on every active Windows playback device. It sends short sound events to the ntfy topic configured in `setting.txt`; it does not read Teams messages or identify their senders.

## Configure

Edit `setting.txt` as UTF-8 before starting:

```text
topicname = your-ntfy-topic
pcname = your-device-name
```

Both values are required. `topicname` selects the ntfy topic and is URL-escaped when building the request URL. `pcname` is included in notification text. The checked-in values are examples and should be replaced with the values for your setup.

## Run and stop

Double-click `start_notification_watcher.bat` to start. Use `stop_notification_watcher.bat` for a cooperative stop. You can also run the script with `-Diagnose`, `-NoSend`, `-DurationSeconds <seconds>`, or `-Threshold <0.0001..1.0>`. `-Stop` requests cooperative shutdown; `-NoSend` suppresses all HTTP requests.

Start, short-sound Received, and Stop events are posted to `https://ntfy.sh/<topicname>`, where `<topicname>` comes from `setting.txt`. Messages use UTF-8, priority 5 (maximum), and Japan Standard Time timestamps. Successful sends and HTTP failures are reported in the console; failed requests are not retried.

## Detection behavior and limits

The default threshold is 0.02. A sound interval closes after 500 ms without a threshold-level sample; intervals up to 1800 ms generate one Received event. These values are retained from the previous implementation because the OCR-restored design text does not reliably show their intended values. Detection is based on sampled session peak levels, not recorded audio. Silent notifications cannot be detected, and other short Teams audio can trigger a notification.

The watcher requires a signed-in Windows desktop session and access to at least one active output device. It does not install a service, configure autostart, use Graph API, record audio, or save audio files.

