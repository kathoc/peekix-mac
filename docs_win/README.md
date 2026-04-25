# Peekix

Peekix is a minimal RTSP camera viewer for Windows first, macOS Apple Silicon second.

The product goal is simple:

> Keep one RTSP camera visible with the least friction possible.

Peekix is not a surveillance suite. It does not aim to manage many cameras, record video, run AI detection, or provide cloud features. It is a lightweight viewer designed to stay open, recover quickly, and let the user glance at a camera feed without ceremony.

## First target

- Windows desktop app
- Distributed as an `.exe` or Windows installer
- Works on a clean Windows environment
- No separate VLC / FFmpeg / GStreamer / Python / Node.js installation required

## Second target

- macOS Apple Silicon `.app`
- Same product behavior as Windows
- Native app bundle with required runtime/components bundled as much as practical

## Later targets

- Android
- iPhone
- Linux

Do not optimize the first version for every future platform. Instead, keep the core connection and reconnection logic separate from the UI so that later ports are possible.

## Preferred technology direction

Start with:

- .NET
- Windows-first desktop UI
- LibVLCSharp for RTSP playback
- Bundled native LibVLC runtime/components

The implementation may choose Avalonia, WinUI, WPF, or another Windows UI stack, but the selection must be justified against the product goal: a stable single-purpose RTSP viewer that can be packaged for clean environments.

## Core value

Peekix succeeds if it does these things well:

1. Launches quickly.
2. Shows the saved RTSP camera automatically.
3. Recovers quickly after network instability.
4. Recovers quickly after sleep/wake.
5. Can stay open for a long time without freezing or leaking memory.
6. Can be used in normal window, fullscreen, or small always-on-top player mode.
