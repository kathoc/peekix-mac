# UI Spec

## Tone

Quiet, light, utilitarian.

Peekix should feel like a small peeking window, not a surveillance command center.

## Main window

Required elements:

- Video area
- Connection status
- Settings button
- Reconnect button
- Fullscreen button
- Mini-player button
- Always-on-top toggle

Optional but useful:

- Last connected time
- Last reconnect reason
- Masked camera address

## First launch

Show a setup screen:

- RTSP URL input
- Save and connect button
- Small note that credentials may be included in the RTSP URL

No complex wizard.

## Normal mode

The main window shows video with minimal chrome.

Status should be visible but not noisy.

## Fullscreen mode

- Video fills the screen.
- Hide unnecessary controls.
- Esc returns to normal mode.
- Mouse movement may reveal minimal controls.

## Mini-player mode

Mini-player is central to the product.

Requirements:

- Small resizable window.
- Video-first layout.
- Minimal or hidden controls.
- Always-on-top can be toggled.
- Easy return to normal mode through right-click menu or small unobtrusive control.
- Remember last mini-player size and position if practical.

## Error and reconnect states

Use calm status text:

- Connecting…
- Reconnecting…
- Camera offline
- Waiting for network…
- Stream stalled. Reconnecting…

Avoid alarming dialogs.
