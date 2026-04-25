# Requirements

## Platform priority

### Phase 1

Windows only.

The Windows version must be the first working product. Do not block the Windows MVP by trying to solve macOS, Android, iPhone, or Linux too early.

### Phase 2

macOS Apple Silicon.

### Phase 3 or later

Android, iPhone, Linux.

## Packaging requirements

Windows:

- Provide an `.exe` or installer.
- Must run on a clean Windows environment.
- Do not require users to install VLC, FFmpeg, GStreamer, Python, Node.js, or any separate media runtime.
- Bundle required native playback components where legally and technically possible.

macOS later:

- Provide Apple Silicon `.app`.
- Avoid requiring the user to install VLC or other runtime separately.
- Document signing and notarization requirements.

## Functional requirements

- First launch shows RTSP URL setup.
- RTSP URL is saved locally.
- Later launches automatically connect to the saved camera.
- User can edit the RTSP URL later.
- User can manually reconnect.
- App shows connection status.
- App supports normal window mode.
- App supports fullscreen mode.
- App supports mini-player mode.
- Mini-player can be set always-on-top.
- Esc exits fullscreen.
- Mini-player can return to normal mode.

## Stability requirements

- Detect RTSP connection failure.
- Detect playback errors.
- Detect stalled frames.
- Detect computer sleep/wake where possible.
- Detect network loss/recovery where possible.
- Reconnect automatically.
- Do not block the UI thread.
- Do not crash when the camera is offline.
- Do not increase memory usage indefinitely during repeated reconnects.

## Security and privacy requirements

- RTSP URLs may include username and password.
- Do not log the full RTSP URL with credentials.
- Mask credentials in UI logs and diagnostics.
- Store settings in the OS-appropriate user settings location.
- Prefer OS-protected storage for credentials if practical.
- Do not transmit settings outside the local app.

## Acceptance criteria for MVP

The MVP is acceptable when:

1. A user can enter an RTSP URL once.
2. The app automatically displays the stream on next launch.
3. The app reconnects after the camera/network is interrupted.
4. The app reconnects after Windows sleep/wake.
5. The app can run for at least 24 hours in a test loop without obvious memory growth or UI freeze.
6. The app can be distributed to a clean Windows machine and run without separate media-runtime installation.
