# Project Brief

## Product Name

**Peekix** (macOS edition). Bundle identifier: `app.peekix.mac`.

## Concept

A "set it and forget it" single-camera RTSP viewer. The user pastes one RTSP URL, the app remembers it, and from then on launching Peekix is the only step required to see the camera. The app is small, fast, native to Apple Silicon, and asks nothing of the host machine.

## Target Users

- Home users with a single IP camera (front door, baby monitor, workshop, garage)
- Small-shop owners who want a live view on a Mac mini or a spare MacBook
- Hobbyists who want a lightweight viewer without running VLC or a browser tab

## User Stories

1. *As a new user*, I open Peekix, paste my RTSP URL, hit Connect, and see the live feed within a couple of seconds.
2. *As a returning user*, I launch Peekix and the previously configured camera connects automatically without any prompts.
3. *As a continuous-viewing user*, I leave Peekix running for days — when the router reboots or the Mac wakes from sleep, the stream comes back on its own.
4. *As a focused user*, I full-screen the camera with one shortcut.
5. *As a multitasker*, I switch to a compact always-on-top mini player so the camera stays visible while I work.
6. *As a careful user*, I want my credentials kept in the macOS Keychain, not in a plain config file.

## Non-Goals

- Recording / DVR functionality
- Multiple simultaneous cameras or grid view
- Motion detection, person/vehicle detection, AI overlays
- Cloud sync, user accounts, telemetry
- ONVIF auto-discovery
- Two-way audio / PTZ control
- Intel-Mac support

## Product Principles

1. **Single camera, single purpose.** Every feature is judged against "does it help one person watch one stream reliably?"
2. **Zero install friction.** Drag the `.app` to `/Applications`, double-click, done. No prerequisites.
3. **Native and small.** Apple Silicon binary, hardware decode, tiny `.app`. We do not ship a browser engine.
4. **Survives the real world.** Wi-Fi drops, ISP hiccups, sleep/wake, and DHCP changes are normal events, not error states.
5. **Quiet UI.** No dashboards, no badges, no popups. The video is the UI.
6. **Conservative defaults.** Auto-reconnect on, mini-player off, hardware decode on, low-latency RTSP transport preferred.
