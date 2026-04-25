# Initial TODO

Prioritized backlog for getting Peekix for Mac from empty repository to a shippable v1. Items are ordered: do them top-to-bottom unless a hard dependency forces an earlier item.

## P0 — Walking skeleton

1. Create the Xcode project under `App/` with the bundle id `app.peekix.mac`, arm64-only, macOS 13 deployment target, hardened runtime + sandbox enabled.
2. Add the four local Swift packages: `PeekixCore`, `PeekixSession`, `PeekixUI`, `PeekixStore`. Wire dependencies as in `ARCHITECTURE.md`.
3. Stand up the SwiftUI + AppKit shell: a single `MainWindowController`, empty toolbar, and a black `CAMetalLayer`-backed view in the content area.
4. Add the SwiftUI `Settings` scene with the URL field only (other preferences come later).
5. `PeekixStore`: implement `SettingsStore` (UserDefaults) and `CredentialsStore` (Keychain). Round-trip a URL through both.

## P0 — Playback core

6. `Scripts/build-ffmpeg.sh`: produce arm64 static libs into `Vendor/ffmpeg/` with the minimal allowlist from `BUILD_AND_PACKAGING.md`.
7. SPM wrapper that links the static libs into `PeekixCore`. Confirm `otool -L` shows zero non-Apple dylibs.
8. `PlaybackEngine`: open RTSP via libavformat, read packets, push to a `VTDecompressionSession`, render `CVPixelBuffer`s through a `MetalRenderer`. End-to-end manual test with a known camera.
9. Wire the engine to the main window so a hardcoded URL plays at app launch.

## P0 — Session and reconnect

10. `PlaybackSession` state machine with the states defined in `RECONNECT_POLICY.md`.
11. Watchdog timer for stall detection (5 s default, 10 s grace at start).
12. Backoff scheduler: 1, 2, 4, 8, 15, 30 s with ±20 % jitter, reset after 10 s of stable playback.
13. `NWPathMonitor` integration with 750 ms debounce; skip-backoff on path change.
14. `NSWorkspace.willSleep` / `didWake` integration; clean teardown on sleep, skip-backoff reconnect on wake.

## P1 — UI completeness

15. Replace the hardcoded URL with the toolbar URL field; commit on Return / focus loss.
16. Status indicator dot + center status overlay with the messages from `UI_SPEC.md`.
17. Full-screen mode (native), with toolbar fade-out after 2 s.
18. Mini-player window (`MiniPlayerWindowController`): borderless, floating, resizable, opacity slider, position/size persisted.
19. Menu bar with the items and shortcuts from `UI_SPEC.md`.
20. Preferences: transport (Auto/TCP/UDP), hardware decode toggle, mute, opacity default, launch-at-login.

## P1 — Reliability hardening

21. 24-hour soak test on a real camera; confirm RSS stays under 200 MB and there are no leaks (Instruments).
22. Yank-the-Ethernet test, sleep-the-Mac test, reboot-the-router test — all must self-recover with no clicks.
23. Log rotation (cap at 10 MB total via `os.Logger` subsystem and a sidecar file if needed).

## P1 — Packaging

24. Developer-ID signing wired into the Xcode project.
25. `Scripts/archive.sh`, `Scripts/notarize.sh`, `Scripts/make-dmg.sh`.
26. Run the clean-machine smoke test from `BUILD_AND_PACKAGING.md`. Block release if anything in that test fails.

## P2 — Polish

27. App icon set (`.icns`) at all required sizes.
28. About window with version and minimal credits.
29. First-run empty state copy.
30. Accessibility audit (VoiceOver labels, full keyboard nav, Reduce Motion).
31. Localization scaffolding (English first; structure permits adding Japanese later).

## Out of scope for v1 (do not start)

- Recording, multi-camera grid, motion/AI detection, ONVIF discovery, PTZ, two-way audio, automatic update channel, telemetry.
