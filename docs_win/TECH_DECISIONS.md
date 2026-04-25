# Technical Decisions

## Current decision

Start with Windows only.

Use .NET and LibVLCSharp unless early prototyping proves it unsuitable.

## Why not Web first

Browsers do not generally play RTSP directly. A Web version would usually require:

```text
RTSP camera → local gateway/server → WebRTC/MSE/HLS → browser
```

That adds another process, port management, failure modes, and security concerns.

Peekix should first be a simple app that opens and shows the camera.

## Why not GStreamer first

GStreamer is powerful and suitable for media pipelines, but its runtime packaging and platform setup can be heavier.

For this project, the packaging requirement is more important than media-pipeline flexibility.

## Why LibVLCSharp first

LibVLCSharp is a cross-platform .NET API over LibVLC. It is designed for video/audio playback and is available for desktop and mobile-oriented .NET use cases.

The main risk is native dependency packaging. Therefore, the first prototype must prove clean-machine deployment early.

## UI framework decision still open

Candidates:

- WPF: Windows-first, simple, mature, but not useful for macOS later.
- WinUI: Windows-native, modern, but packaging can be more complex.
- Avalonia: cross-platform UI, useful for macOS later.
- .NET MAUI: useful for future mobile, but Windows desktop packaging and video-view details must be validated.

Recommended approach:

1. Prototype RTSP playback and reconnect behavior first.
2. Choose UI framework after confirming playback control and packaging path.
3. Keep Core independent of UI.

## Current bias

For Windows MVP:

- If fastest reliable Windows build matters: WPF + LibVLCSharp.
- If macOS follow-up matters soon: Avalonia + LibVLCSharp.
- If mobile follow-up becomes primary: .NET MAUI + LibVLCSharp.MAUI.

Do not let future mobile support delay the Windows MVP.
