# Technology Decisions

## Summary

| Concern | Decision |
|---|---|
| Language | Swift 5.9+ |
| UI framework | SwiftUI (views) + AppKit (window controllers) |
| RTSP demux | Bundled FFmpeg (libavformat/libavcodec) static libs, arm64 |
| Video decode | Apple **VideoToolbox** (hardware H.264 / HEVC) |
| Render | **Metal** via `CAMetalLayer` |
| Settings storage | `UserDefaults` |
| Secrets storage | macOS Keychain (`Security.framework`) |
| Build system | Xcode 15+, Swift Package Manager for in-repo modules |
| Packaging | Single `.app` bundle (arm64 only), Developer-ID signed and notarized; optional `.dmg` |

## Recommended Stack: Swift + Bundled FFmpeg + VideoToolbox + Metal

This is the chosen stack. Rationale below.

### Why this combination

1. **Dependency-free for the user.** FFmpeg is compiled to static libraries and embedded in the `.app`. The user installs nothing — no Homebrew, no VLC, no FFmpeg CLI.
2. **Smallest viable size.** A trimmed FFmpeg build (only RTSP/RTP demuxers, H.264/HEVC parsers, no encoders, no filters, no protocols beyond `rtsp,rtp,tcp,udp,file`) fits well under 10 MB on arm64. The total `.app` stays under our 25 MB target.
3. **Native hardware decode.** VideoToolbox uses the Apple Silicon media engine for H.264 and HEVC. CPU stays cold; battery and thermals stay calm during 24/7 viewing.
4. **First-class macOS integration.** Metal rendering plays nicely with full screen, Mission Control, multi-display, HiDPI, and ProMotion. Sleep/wake and color management are handled by the OS.
5. **Predictable reconnect.** We own the FFmpeg session, so we can tear it down and rebuild it deterministically in response to `NWPathMonitor` and sleep/wake events.
6. **Signing & notarization are simple.** No third-party frameworks with bespoke embedded helpers, no XPC sub-bundles. Every binary inside the `.app` is ours and gets signed in one pass.
7. **Apple Silicon first.** No fat binaries. Build flags target `arm64-apple-macos13` exclusively.

### Build inputs

- FFmpeg ≥ 6.1, configured with `--enable-static --disable-shared --disable-programs --disable-doc --disable-everything` and a minimal allowlist (RTSP/RTP/TCP/UDP protocols, H.264/HEVC parsers, AAC parser if audio is enabled later, image converters as needed).
- Headers vendored alongside the static libs in `Vendor/ffmpeg/`.
- A thin C bridging layer exposes only what `PeekixCore` needs (open RTSP, read packet, close); the rest of the codebase is pure Swift.

## Alternatives considered

### A. AVFoundation only
**Rejected.** `AVPlayer` does not natively speak RTSP. Wrapping a local proxy (e.g., HLS rebroadcast) adds latency, complexity, and a second background process — exactly the dependencies we are trying to avoid.

### B. VLCKit (libVLC for macOS)
**Rejected as primary.** VLCKit is mature and dependency-internal, but:
- The framework adds 60–150 MB to the bundle, blowing past the size target.
- It pulls in a large surface of plugins we will never use (encoders, filters, many protocols), increasing attack surface and notarization friction.
- Reconnect semantics are coarser; we want bit-level control of the session lifecycle for the long-running-stability requirement.
- Hardware decode works but is one indirection removed from VideoToolbox, making it harder to diagnose performance regressions.

It remains a viable fallback if the FFmpeg build proves too costly to maintain, but is not the v1 choice.

### C. GStreamer
**Rejected.** Even larger than VLCKit, plugin-based architecture complicates notarization, and arm64 macOS support is less polished than FFmpeg's.

### D. WebRTC / browser-based viewer (WKWebView)
**Rejected.** Cameras speak RTSP, not WebRTC, so this would require an embedded translation server. Defeats the dependency-free goal.

## UI: SwiftUI vs AppKit

We use **SwiftUI for content views** (toolbar, status overlays, preferences) and **AppKit for window controllers** (window level, collection behavior, full-screen toggling, always-on-top). Pure SwiftUI on macOS still has gaps around floating-window behavior; mixing keeps the simple parts simple and gives us full control where SwiftUI falls short.

## Settings storage: UserDefaults vs file vs Core Data

`UserDefaults` is the right size for our needs: a handful of scalar settings and the last-used URL components. A JSON config file would require us to invent a path, handle migrations, and explain it to users. Core Data is overkill. Credentials live in the Keychain.

## Build system

- **Xcode + SPM** (no CocoaPods, no Carthage). Local Swift packages keep modules clean; the FFmpeg static libs are linked via a system-library SPM target wrapping `Vendor/ffmpeg/`.
- Continuous-integration-friendly: `xcodebuild archive` produces the signed bundle.

## Out-of-scope technologies (do not introduce)

- .NET, WPF, WinUI, Avalonia, LibVLCSharp, MAUI, anything Windows-flavored.
- Electron, Tauri, or any web-runtime wrapper.
- Python, Node, Ruby — neither at runtime nor in user-facing tooling.
- Rosetta 2 / x86_64 build outputs.
