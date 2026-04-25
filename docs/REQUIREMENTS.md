# Requirements

## Functional Requirements

### F1. Stream Source
- F1.1 Accept a single RTSP URL of the form `rtsp://[user:pass@]host[:port]/path`.
- F1.2 Support both TCP and UDP RTSP transports; prefer TCP by default for NAT-friendly behavior.
- F1.3 Support H.264 and H.265 (HEVC) video. Audio is optional and muted by default.
- F1.4 Persist the last URL across launches and auto-connect on next launch.
- F1.5 Store credentials in the macOS Keychain, not in plain text.

### F2. Playback
- F2.1 Display live video with hardware-accelerated decode.
- F2.2 Provide visible state: connecting, playing, reconnecting, error.
- F2.3 Manual disconnect / reconnect controls.
- F2.4 Aspect-ratio preserving render with letterboxing.

### F3. View Modes
- F3.1 Standard window with a minimal toolbar (URL field, connect/disconnect, mode buttons).
- F3.2 Full-screen mode (native macOS full screen).
- F3.3 Compact always-on-top mini player (resizable, draggable, no chrome by default, opacity adjustable).
- F3.4 Toggle between modes via menu items and keyboard shortcuts.

### F4. Reliability
- F4.1 Auto-reconnect on stream errors with exponential backoff.
- F4.2 On macOS sleep/wake, pause and resume cleanly.
- F4.3 On network-path change (Wi-Fi switch, Ethernet plug/unplug), tear down and rebuild the session.
- F4.4 Recover from prolonged outages (hours) without restart.

### F5. Settings
- F5.1 Preferences window: URL, transport (auto/TCP/UDP), hardware decode toggle, audio mute, mini-player opacity, launch-at-login toggle.
- F5.2 Settings persisted in `UserDefaults`; secrets in Keychain.

## Non-Functional Requirements

### N1. Performance Targets
- N1.1 Cold launch to first video frame: ≤ 3 s on M1/M2/M3 over LAN with a 1080p H.264 stream.
- N1.2 Steady-state CPU on M1: ≤ 8 % single-core for 1080p30 H.264, ≤ 12 % for 1080p30 H.265.
- N1.3 Steady-state RSS: ≤ 200 MB after 24 h of continuous playback.
- N1.4 Memory growth over 7 days of continuous playback: ≤ 50 MB.
- N1.5 `.app` bundle size: ≤ 25 MB (target), hard cap ≤ 60 MB.

### N2. Reconnect SLA
- N2.1 Detect a stalled stream within 5 s of last received packet.
- N2.2 First reconnect attempt within 1 s of detected failure.
- N2.3 Backoff sequence: 1 s, 2 s, 4 s, 8 s, 15 s, capped at 30 s; reset on success.
- N2.4 Network-path change triggers an immediate reconnect (skip backoff).

### N3. Stability
- N3.1 Run continuously for ≥ 30 days without crash, leak, or UI freeze in test rig.
- N3.2 No unbounded log files; rotate or cap at 10 MB.

### N4. Compatibility
- N4.1 macOS 13 Ventura and later.
- N4.2 Apple Silicon only (arm64). The binary is not produced for x86_64.
- N4.3 Tested against common camera firmwares: Reolink, Hikvision, Dahua, TP-Link Tapo, Amcrest, Axis.

### N5. Distribution
- N5.1 Single `.app` bundle, signed with a Developer ID certificate.
- N5.2 Notarized and stapled.
- N5.3 Optional `.dmg` for distribution.
- N5.4 No installers, no helper services.

### N6. Privacy
- N6.1 No telemetry, no analytics, no network calls except to the configured RTSP host.
- N6.2 No automatic update channel in v1; updates are manual `.dmg` swaps.
