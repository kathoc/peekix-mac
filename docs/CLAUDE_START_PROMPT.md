# Claude Code — Start Prompt for `peekix-mac`

Paste the section below as the very first message of a fresh Claude Code session opened in the `peekix-mac` repository. It contains every constraint and reading order needed to begin implementation.

---

You are starting implementation of **Peekix for Mac** (`peekix-mac`), a brand-new macOS application. Before writing any code, read every file in `docs/` in this order: `README.md`, `PROJECT_BRIEF.md`, `REQUIREMENTS.md`, `TECH_DECISIONS.md`, `ARCHITECTURE.md`, `UI_SPEC.md`, `RECONNECT_POLICY.md`, `BUILD_AND_PACKAGING.md`, `TODO.md`. These documents are the single source of truth for this project.

## Hard constraints — never violate

1. **Apple Silicon only.** All build outputs target `arm64-apple-macos13` exclusively. No fat binaries, no x86_64, no Rosetta. Set `ARCHS = arm64` and remove `x86_64` from `VALID_ARCHS`.
2. **macOS 13 (Ventura) or later** as the deployment target.
3. **Zero external dependencies for the end user.** A clean macOS install must launch and use the app with no Homebrew, no VLC, no FFmpeg CLI, no Python/Node/Ruby, no helper services. Anything required at runtime ships **inside the `.app` bundle**.
4. **Lightweight.** Target `.app` size ≤ 25 MB; hard cap 60 MB. Cold launch to first frame ≤ 3 s on M1.
5. **Stack is fixed:** Swift 5.9+, SwiftUI for views, AppKit for window controllers, bundled FFmpeg (static, arm64) for RTSP demux, VideoToolbox for hardware decode, Metal for rendering, `UserDefaults` for settings, Keychain for credentials. Do **not** introduce VLCKit, GStreamer, WebRTC bridges, Electron, or any web runtime.
6. **No prior-Windows references.** Do not look at any sibling directory, do not assume a Windows codebase exists, and do not introduce .NET, WPF, WinUI, Avalonia, MAUI, or LibVLCSharp. This project is a Mac-native product designed from scratch.
7. **One camera, one stream.** No recording, no multi-camera grids, no detection, no cloud, no accounts, no ONVIF discovery in v1.

## Project identity

- Product name: **Peekix**
- Bundle id: `app.peekix.mac`
- Distribution: single Developer-ID-signed, notarized `.app`; optional `.dmg`
- Repo root: `peekix-mac/`

## What to do first (scaffold step)

Work through `docs/TODO.md` from the top. Specifically, the first scaffold pass is:

1. Create the Xcode project at `App/Peekix.xcodeproj` (bundle id `app.peekix.mac`, arm64-only, macOS 13 deployment target, hardened runtime + sandbox enabled with the `network.client` entitlement, Developer-ID signing placeholder).
2. Create the four local Swift packages under `Packages/`: `PeekixCore`, `PeekixSession`, `PeekixUI`, `PeekixStore`. Wire dependencies as defined in `docs/ARCHITECTURE.md` (`App` → all; `PeekixSession` → `PeekixCore`; `PeekixUI` → `PeekixSession` + `PeekixStore`).
3. Stub `PeekixStore` with a working `SettingsStore` (UserDefaults) and `CredentialsStore` (Keychain) that round-trips a string and a password.
4. Stand up the SwiftUI + AppKit app shell: a single `MainWindowController` containing a toolbar (URL field, Connect button placeholder, status dot placeholder) and a black `CAMetalLayer`-backed video view filling the content area. Add a SwiftUI `Settings` scene with the URL field only.
5. Add `Scripts/build-ffmpeg.sh` matching the configure invocation in `docs/BUILD_AND_PACKAGING.md`. Run it; check the resulting static libs into `Vendor/ffmpeg/lib/` with headers in `Vendor/ffmpeg/include/`.
6. Link the FFmpeg static libs into `PeekixCore` via an SPM wrapper. Add a smoke test that calls `avformat_version()` from Swift and prints it on launch. Confirm `otool -L` on the built binary lists **only** Apple-shipped dylibs.
7. Commit at this point — this is the agreed walking-skeleton checkpoint. Then move to playback (FFmpeg RTSP demux → VideoToolbox decode → Metal render) per the `P0 — Playback core` section of `docs/TODO.md`.

## Working agreements

- Keep modules clean: cross-layer communication is one-way as described in `docs/ARCHITECTURE.md`.
- Never persist passwords in `UserDefaults`; always use the Keychain.
- Every reconnect attempt — its trigger, attempt index, and delay — must be logged through `os.Logger` with subsystem `app.peekix.mac`.
- Treat the clean-machine smoke test in `docs/BUILD_AND_PACKAGING.md` as the release gate. If `otool -L` shows any non-Apple dylib in the final binary, the build is not shippable.
- When adding configuration knobs, prefer conservative defaults (TCP transport, hardware decode on, audio muted, mini-player off).

Begin by reading `docs/` in the order listed above, then execute the scaffold step. Ask before deviating from `docs/TECH_DECISIONS.md`.
