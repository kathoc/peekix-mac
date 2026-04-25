# TODO

## Prototype 0: technical spike

- [x] Create solution structure.
- [x] Pick initial Windows UI framework.
- [x] Add playback library.
- [x] Play RTSP URL from saved user config.
- [x] Verify no system-installed VLC dependency is required, or document what is still missing.
- [ ] Test camera disconnect/reconnect behavior manually.

## Prototype 1: usable Windows MVP

- [x] First-launch RTSP URL setup.
- [x] Save RTSP URL.
- [x] Auto-connect on app launch.
- [x] Manual reconnect button.
- [x] Connection status display.
- [x] Automatic reconnect on playback failure.
- [x] Frame stall detection.
- [x] Sleep/wake reconnect.
- [x] Network recovery reconnect.
- [x] Normal window mode.
- [x] Fullscreen mode.
- [x] Mini-player mode.
- [x] Always-on-top toggle.

## Packaging

- [ ] Self-contained publish test.
- [ ] Clean Windows VM or Windows Sandbox test.
- [ ] Native media library bundling test.
- [ ] Decide portable folder vs installer.
- [x] Add build script.
- [ ] Add release checklist.

## Quality

- [ ] 24-hour run test.
- [ ] Repeated reconnect memory test.
- [ ] Sleep/wake test.
- [ ] Network unplug/replug test.
- [ ] Wrong URL test.
- [ ] Offline camera test.
- [ ] Credential masking test.

## Later

- [ ] macOS Apple Silicon feasibility test.
- [ ] macOS `.app` packaging test.
- [ ] Android feasibility test.
- [ ] iPhone feasibility test.
- [ ] Linux feasibility test.
