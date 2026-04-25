# Peekix for Mac

A minimal, dependency-free single-camera RTSP viewer for macOS on Apple Silicon.

## Target

- macOS 13 Ventura or later
- Apple Silicon (arm64) only — Intel Macs are out of scope
- Single distributable `.app` (optionally wrapped in a `.dmg`)
- No external runtime requirements: a clean macOS install can launch and use the app without installing VLC, FFmpeg, Homebrew, Python, Node, or any other tooling

## Core Value

- Type an RTSP URL once, and the camera shows up immediately on every launch
- Stays alive for weeks: survives Wi-Fi blips, sleep/wake, and router reboots without growing memory or freezing
- Three viewing modes: standard window, full screen, and a compact always-on-top player
- Tiny binary, native Apple Silicon, hardware-accelerated decoding

## Non-Goals

- Recording, motion/AI detection, multi-camera grids, cloud, accounts, ONVIF discovery

## Documentation

- `PROJECT_BRIEF.md` — concept, user stories, principles
- `REQUIREMENTS.md` — functional and non-functional requirements
- `ARCHITECTURE.md` — Mac-specific layered design
- `TECH_DECISIONS.md` — chosen stack and rejected alternatives
- `UI_SPEC.md` — window, full screen, mini player, preferences
- `RECONNECT_POLICY.md` — disconnect, sleep/wake, network-change recovery
- `BUILD_AND_PACKAGING.md` — Xcode, signing, notarization, `.dmg`
- `TODO.md` — prioritized initial backlog
- `CLAUDE_START_PROMPT.md` — kickoff prompt for the implementation session
