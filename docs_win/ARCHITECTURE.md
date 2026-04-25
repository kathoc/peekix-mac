# Architecture

## Recommended structure

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

## Layer responsibilities

### Peekix.App

UI only.

Responsibilities:

- Main window
- Fullscreen window state
- Mini-player window state
- Always-on-top toggle
- Settings screen
- Connection status display
- User commands such as reconnect and edit URL

Do not put RTSP reconnection policy directly in UI code.

### Peekix.Core

Platform-independent application logic.

Responsibilities:

- Camera profile model
- Connection state model
- Reconnection state machine
- Backoff policy
- Stream health model
- Events for status changes
- Interfaces for media playback, sleep/wake detection, network detection, settings storage

### Peekix.Infrastructure

Concrete services that are not pure UI but may still be shared.

Responsibilities:

- Settings serialization
- Credential masking
- Diagnostics logging
- App configuration
- Optional encrypted storage adapter

### Peekix.Platform.Windows

Windows-specific implementations.

Responsibilities:

- Sleep/wake event detection
- Network availability detection
- Windows settings path
- Windows always-on-top behavior
- Windows packaging helpers
- Native LibVLC location/bootstrap if required

## Playback abstraction

Use an interface similar to:

```csharp
public interface ICameraPlaybackSession : IAsyncDisposable
{
    event EventHandler<PlaybackStateChangedEventArgs> StateChanged;
    event EventHandler<FrameHeartbeatEventArgs> FrameHeartbeat;

    Task StartAsync(CameraProfile profile, CancellationToken cancellationToken);
    Task StopAsync(CancellationToken cancellationToken);
}
```

The UI should not directly own reconnect loops. The connection manager owns reconnect decisions.

## Connection manager

Use a long-lived connection manager that owns the active playback session.

Responsibilities:

- Start playback
- Stop playback
- Dispose broken playback sessions
- Create new playback sessions
- Track health
- Trigger reconnects
- Reset backoff on success

## Important design rule

When a stream is unhealthy, do not try to patch the current session indefinitely.

Destroy the current playback session and create a fresh RTSP session.

This is less elegant but usually more reliable for unstable RTSP cameras.
