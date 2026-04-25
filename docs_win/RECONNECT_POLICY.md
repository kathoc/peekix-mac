# Reconnect Policy

## Goal

Reconnect as quickly as possible without freezing the UI or creating a tight CPU loop.

## Failure signals

Treat these as reconnect triggers:

- RTSP connection failed.
- Media player reported an error.
- Playback stopped unexpectedly.
- No new frame heartbeat for a configured timeout.
- Network became unavailable.
- Network became available again.
- Windows resumed from sleep.
- User clicked reconnect.

## Backoff policy

Use this retry schedule:

```text
0s → 0.5s → 1s → 2s → 3s → 5s → 5s → 5s ...
```

Rules:

- First reconnect should be immediate.
- Cap retry delay at 5 seconds.
- Reset backoff after successful playback has been stable for a short period.
- Sleep/wake and network-recovery events bypass current backoff and reconnect immediately.
- Manual reconnect also bypasses backoff.

## Session disposal rule

On reconnect:

1. Mark old session as obsolete.
2. Stop playback.
3. Dispose native/media resources.
4. Wait briefly if needed for native resources to release.
5. Create a new playback session.
6. Start playback with the saved RTSP URL.

## Frame stall detection

If possible, track video heartbeat.

A stream is considered stalled when:

- The player says it is playing, but
- No video frame or playback time movement is observed for a configured duration.

Suggested defaults:

```text
Initial startup timeout: 10 seconds
Frame stall timeout: 5 seconds
Stable playback reset threshold: 20 seconds
```

Tune these values after real camera testing.

## UI behavior during reconnect

- Keep the app responsive.
- Show a small status such as “Reconnecting…”
- Do not show modal dialogs for normal disconnects.
- Do not require user action.

## Logging rule

Log state transitions, but never log full RTSP URLs containing credentials.

Good:

```text
rtsp://user:****@192.168.1.20:554/stream1
```

Bad:

```text
rtsp://user:password@192.168.1.20:554/stream1
```
