# Architecture

Peekix for Mac is a single-process Swift application built around four cleanly separated layers. Each layer can be unit-tested in isolation; cross-layer communication is one-way (UI observes, core publishes).

```
┌────────────────────────────────────────────────────────┐
│                       UI Layer                         │
│   SwiftUI views + AppKit window controllers            │
│   Standard window · Full screen · Mini player · Prefs  │
└──────────────▲────────────────────────────┬────────────┘
               │ @Published state           │ user intents
               │                            ▼
┌──────────────┴────────────────────────────────────────┐
│              Session / Reconnect Layer                 │
│   PlaybackSession state machine                        │
│   NWPathMonitor · NSWorkspace sleep/wake notifications │
│   Backoff scheduler                                    │
└──────────────▲────────────────────────────┬────────────┘
               │ frames, status             │ start/stop
               │                            ▼
┌──────────────┴────────────────────────────────────────┐
│                   Playback Core                        │
│   RTSP demux · H.264/H.265 decode · clock · render     │
│   (bundled FFmpeg + VideoToolbox + Metal)              │
└──────────────▲────────────────────────────┬────────────┘
               │ decoded frames             │ url, transport
               │                            ▼
┌──────────────┴────────────────────────────────────────┐
│                  Persistence Layer                     │
│   UserDefaults (settings) · Keychain (credentials)     │
└────────────────────────────────────────────────────────┘
```

## Layer Responsibilities

### 1. Playback Core (`PeekixCore`)
- Owns the bundled FFmpeg static libraries (libavformat, libavcodec, libavutil, libswscale, libswresample).
- Exposes a Swift-friendly façade: `PlaybackEngine` with `start(url:transport:options:)`, `stop()`, and a delegate for frame and status callbacks.
- RTSP session is opened via libavformat. Compressed packets are pushed into a `VTDecompressionSession` (VideoToolbox) for hardware decode.
- Decoded `CVPixelBuffer`s are handed to a `MetalRenderer` that draws to a `CAMetalLayer` hosted in the UI.
- Clock: presentation timestamps drive a low-latency render queue (target end-to-end latency: < 500 ms LAN).
- All FFmpeg interaction happens on a dedicated serial dispatch queue. The Metal layer renders on the main thread via `CADisplayLink`-equivalent (`CVDisplayLink`).

### 2. Session / Reconnect Layer (`PeekixSession`)
- `PlaybackSession` is a state machine: `idle → connecting → playing → stalled → reconnecting → playing | failed`.
- Watchdog timer fires when no frame has arrived within `stallTimeout`.
- Subscribes to:
  - `NWPathMonitor` — network path changes
  - `NSWorkspace.willSleepNotification` / `didWakeNotification` — system sleep/wake
- Emits `@Published` status to the UI (`SessionStatus` enum: `.idle`, `.connecting`, `.playing`, `.reconnecting(attempt:)`, `.failed(reason:)`).
- Owns the backoff scheduler. See `RECONNECT_POLICY.md`.

### 3. UI Layer (`PeekixUI`)
- SwiftUI for views, AppKit for window-level concerns (level, collection behavior, full screen, always-on-top).
- Three window controllers:
  - `MainWindowController` — standard window with toolbar
  - `MiniPlayerWindowController` — borderless, `.floating` level, resizable, opacity-aware
  - Full-screen is a state of `MainWindowController`, not a separate window
- A single `PreferencesScene` (SwiftUI `Settings` scene).
- The video surface is an `NSViewRepresentable` wrapping a `CAMetalLayer`-backed `NSView`, owned by the playback core.

### 4. Persistence Layer (`PeekixStore`)
- `SettingsStore`: typed wrapper over `UserDefaults` (transport, hardware-decode toggle, mute, opacity, launch-at-login, last URL host/port/path).
- `CredentialsStore`: thin wrapper over the Keychain (`kSecClassInternetPassword`) keyed by host+port+username.
- The full RTSP URL is reconstructed at runtime from settings + Keychain; we never persist the password in `UserDefaults`.

## Concurrency Model

- One serial queue per active RTSP session for FFmpeg I/O.
- VideoToolbox callbacks run on its internal queue; we hop to the renderer queue immediately.
- Renderer runs on the main thread (Metal main-thread checker friendly).
- `PlaybackSession` is an `@MainActor` class; backoff timers use `Task.sleep` cancellation, not `Timer`.

## Module Layout (Swift Package + Xcode App)

```
peekix-mac/
├── App/                       # Xcode app target (entry point, Info.plist, assets)
├── Packages/
│   ├── PeekixCore/            # FFmpeg + VideoToolbox + Metal playback engine
│   ├── PeekixSession/         # State machine, reconnect, NWPathMonitor, sleep/wake
│   ├── PeekixUI/              # SwiftUI views, window controllers
│   └── PeekixStore/           # UserDefaults + Keychain
└── Vendor/
    └── ffmpeg/                # Prebuilt arm64 static libs + headers
```

The app target depends on the four local Swift packages; the packages do not depend on each other except `App` → all, `PeekixSession` → `PeekixCore`, `PeekixUI` → `PeekixSession` + `PeekixStore`.

## Failure Boundaries

- A decode error never crashes the app; it surfaces as a `SessionStatus.reconnecting`.
- A bad URL is rejected before the session starts.
- All logging goes through `os.Logger` with subsystem `app.peekix.mac`.
