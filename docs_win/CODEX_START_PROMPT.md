# Codex Start Prompt

You are building a Windows-first desktop app named Peekix.

Peekix is a lightweight single-purpose RTSP camera viewer. Its product purpose is not “camera management,” but “quickly peeking at one camera feed.”

Build this project with a strong bias toward reliability, quick reconnect, and clean-machine distribution.

## Current scope

Phase 1 is Windows only.

Mac Apple Silicon support comes later.

Android, iPhone, and Linux are future possibilities, but they must not slow down the Windows MVP.

## Product requirements

The app must:

1. Let the user enter one RTSP URL on first launch.
2. Save the RTSP URL locally.
3. Automatically connect to the saved RTSP URL on later launches.
4. Display the camera feed as quickly as possible.
5. Reconnect automatically when the stream fails.
6. Reconnect automatically after Windows sleep/wake.
7. Reconnect automatically after network loss/recovery where possible.
8. Provide normal window mode.
9. Provide fullscreen mode.
10. Provide mini-player mode.
11. Let the mini-player be always-on-top.
12. Run for long periods without UI freezes or obvious memory growth.
13. Be packageable so it works on a clean Windows environment without asking the user to install VLC, FFmpeg, GStreamer, Python, Node.js, or other media runtimes separately.

## Non-goals

Do not implement these in the MVP:

- Multiple cameras
- Recording
- Motion detection
- AI detection
- Cloud features
- User accounts
- Remote access service
- Timeline playback
- Camera discovery

## Technology direction

Use .NET.

Use LibVLCSharp or a similarly practical RTSP playback engine that can be bundled with the app.

Do not depend on system-installed VLC.

Before writing a large UI, first validate:

1. RTSP playback works.
2. Native playback dependencies can be bundled.
3. The app can reconnect by fully destroying and recreating the playback session.
4. A self-contained or installer-based Windows build can run on a clean Windows environment.

## Architecture requirements

Create a structure similar to:

```text
peekix/
├── src/
│   ├── Peekix.App/
│   ├── Peekix.Core/
│   ├── Peekix.Platform.Windows/
│   └── Peekix.Infrastructure/
├── assets/
├── build/
├── docs/
└── tests/
```

Keep RTSP connection and reconnection logic out of UI code.

Core should contain:

- Camera profile model
- Connection state model
- Reconnection state machine
- Backoff policy
- Stream health model
- Interfaces for playback, settings, platform events, and logging

Windows platform layer should contain:

- Sleep/wake event detection
- Network availability detection
- Windows-specific always-on-top support if needed
- Windows settings path
- Native playback bootstrap if needed

Infrastructure should contain:

- Settings persistence
- Credential masking
- Diagnostics logging

## Reconnect policy

Reconnect triggers:

- RTSP connection failed
- Media playback error
- Playback stopped unexpectedly
- Frame stall detected
- Network became unavailable
- Network became available again
- Windows resumed from sleep
- Manual reconnect requested

Backoff:

```text
0s → 0.5s → 1s → 2s → 3s → 5s → 5s ...
```

Rules:

- First reconnect is immediate.
- Cap retry delay at 5 seconds.
- Reset backoff after stable playback.
- Sleep/wake and network-recovery events bypass backoff and reconnect immediately.
- Manual reconnect bypasses backoff.
- UI thread must never be blocked.

On reconnect, fully dispose the previous playback session and create a new one.

## UI requirements

Main window:

- Video area
- Connection status
- Settings
- Reconnect
- Fullscreen
- Mini-player
- Always-on-top toggle

Fullscreen:

- Video fills screen
- Esc returns to normal

Mini-player:

- Small resizable window
- Video-first UI
- Always-on-top toggle
- Return to normal mode via small control or context menu
- Remember size/position if practical

## Security rules

RTSP URLs may contain credentials.

Do not log full credentials.

Mask credentials in logs and status output.

Example:

```text
rtsp://user:****@192.168.1.20:554/stream1
```

## First task

Inspect the repository. If it is empty, create the initial solution structure and a minimal Windows prototype.

The first prototype should prioritize:

1. Showing a test RTSP stream.
2. Saving and loading one RTSP URL.
3. Manual reconnect.
4. Automatic reconnect after playback failure.
5. Basic packaging notes.

After creating the first version, update README.md with:

- Chosen UI framework
- Chosen playback library
- How to run
- How to publish for Windows
- Known limitations
- What still needs validation on a clean Windows machine
