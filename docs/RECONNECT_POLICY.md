# Reconnect Policy

Peekix is designed to keep showing the camera through ordinary disruptions without user intervention. This document defines exactly when, how, and how often we reconnect.

## Triggers

Reconnect is initiated by any of:

1. **Stream stall** — no video packet received for `stallTimeout` (default 5 s) while in the `.playing` state.
2. **FFmpeg / VideoToolbox error** — `av_read_frame` returns a fatal error, the RTSP session times out, or the decompression session reports an unrecoverable state.
3. **Network path change** — `NWPathMonitor` reports a new path (interface change, Wi-Fi roam, Ethernet plug/unplug, captive portal exit).
4. **System wake** — `NSWorkspace.didWakeNotification` fires after a sleep.
5. **Manual** — user clicks Retry or selects Stream → Reconnect.

## State Machine

```
idle ─start──▶ connecting ─open ok──▶ playing
                  │                      │
                  │ open fail            │ stall / error
                  ▼                      ▼
               reconnecting ◀────────────┘
                  │   ▲
                  │   │ retry
                  │   │
                  ▼   │
            connecting (retry)
                  │
       give-up ▶ failed (still backing off in background)
                  │
                manual retry / network change ─▶ connecting
```

`idle` is entered only on app launch (before first connect) and on manual disconnect. `failed` is a *display* state; the scheduler keeps trying behind the overlay.

## Backoff Schedule

Default retry delays, in seconds:

```
1, 2, 4, 8, 15, 30, 30, 30, …
```

- The cap is 30 s.
- The sequence resets to the start whenever a connect succeeds and the session reaches `.playing` for at least 10 s.
- Each delay is jittered by ±20 % to avoid synchronized retry storms when many clients restart together.

## Skip-Backoff Cases

These reconnect immediately, ignoring the current backoff slot:

- A `NWPathMonitor` path change while in `reconnecting` or `failed`.
- `NSWorkspace.didWakeNotification`.
- Manual user retry.

After a skip-backoff connect, if it still fails, the schedule resumes from the slot it would otherwise be at.

## Sleep / Wake

- On `willSleepNotification`: tear down the FFmpeg session and the VideoToolbox decompression session cleanly. Do not rely on the OS to pause network I/O.
- On `didWakeNotification`: wait 500 ms (let `NWPathMonitor` settle), then reconnect with skip-backoff.
- The UI shows `Reconnecting…` during this window; we do not display sleep/wake as an error.

## Network-Path Changes

- A debounce of 750 ms is applied to `NWPathMonitor` updates so that brief flaps don't cause double reconnects.
- If the new path reports `.unsatisfied`, we move to `reconnecting` and pause attempts (display `Waiting for network…`) until a satisfied path returns.
- If the new path is satisfied but expensive (`.cellular` constrained), we still attempt — the user knowingly entered the URL.

## Stall Detection Details

- The watchdog runs on the session queue and checks `lastFrameTimestamp` every 1 s.
- `stallTimeout` is 5 s by default. It is increased to 10 s for the first 15 s after a successful connect, to absorb slow-starting cameras.
- On stall: cancel any in-flight read, close the RTSP session, transition to `reconnecting`.

## Failure Surfacing

- The first 5 reconnect attempts are silent (status badge yellow, overlay text `Reconnecting…`).
- After the 5th consecutive failure, the overlay adds the underlying reason (`Host unreachable`, `Authentication failed`, `Stream not found`, etc.) and a manual `Retry` button.
- We **never** stop retrying on our own. The user's choices to halt are: click Disconnect, or quit the app.

## Authentication Failures

- A `401 Unauthorized` from the camera halts retries until the user updates credentials. We surface a clear `Authentication failed — open Preferences` overlay; backoff is paused.
- All other HTTP-like RTSP statuses are treated as transient and retried.

## Resource Hygiene

- Every `connect` allocates a new FFmpeg context and VideoToolbox session; every `disconnect` releases them on a serial queue and waits for completion before allocating again. This is the single most important rule for 30-day stability.
- Logs include `attempt`, `delay`, `reason` for every transition; log volume is rate-limited to one line per state change.
