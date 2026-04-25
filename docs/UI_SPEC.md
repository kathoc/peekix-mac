# UI Specification

All screens follow the macOS Human Interface Guidelines. The video is the focus; chrome is minimal and gets out of the way.

## Windows and Modes

### 1. Standard Window

- Default size on first launch: 960 × 540 (16:9), centered on the active display.
- Resizable, with a minimum size of 480 × 270.
- Title bar uses `.unifiedCompact` style.
- Toolbar items (left to right):
  - URL field (single line, editable, placeholder `rtsp://user:pass@host/stream`)
  - Connect / Disconnect button (state-aware label)
  - Status indicator (small dot: gray idle, yellow connecting/reconnecting, green playing, red failed)
  - Spacer
  - Mode buttons: full-screen, mini-player
- Video surface fills the content area below the toolbar with letterboxed aspect-preserving render.
- Status overlay (centered, semi-transparent rounded rectangle) appears only when not `.playing`:
  - `Connecting…`
  - `Reconnecting (attempt N)…`
  - `Disconnected — <short reason>`  with a `Retry` button
- Double-click the video surface toggles full screen.

### 2. Full Screen

- Native macOS full screen (`toggleFullScreen:`); the menu bar auto-hides.
- Toolbar fades out after 2 s of mouse inactivity, fades in on cursor movement.
- Esc exits full screen.
- Status overlay rules are identical to the standard window.

### 3. Mini Player (Always-on-Top)

- Borderless window (`.borderless`) at `.floating` window level (above normal windows, below modal panels).
- Default size: 320 × 180. Resizable while preserving aspect ratio.
- Drag from anywhere on the video to move; resize from any edge.
- Right-click context menu:
  - Return to standard window
  - Enter full screen
  - Opacity slider (50 %–100 %)
  - Close
- Stays visible across Spaces (`collectionBehavior` includes `.canJoinAllSpaces`, `.fullScreenAuxiliary`).
- Hover reveals a small Close button in the top-left.
- Position and size are remembered across launches.

### 4. Preferences

A SwiftUI `Settings` scene with two tabs:

**Stream**
- RTSP URL (text field, secured: password masked when displayed)
- Transport: Auto / TCP / UDP (segmented control, default Auto)
- Hardware decode (toggle, default on)
- Mute audio (toggle, default on)

**General**
- Launch at login (toggle, default off)
- Mini-player default opacity (slider 50 %–100 %, default 100 %)
- Status overlay auto-hide delay (2 s / 4 s / Never)
- Reset all settings (button with confirmation alert)

Changes apply immediately; there is no Save button. Closing the URL field commits the value and triggers a reconnect if the URL changed.

## Menus

### Peekix
- About Peekix
- Preferences… (⌘,)
- Services
- Hide / Hide Others / Show All
- Quit Peekix (⌘Q)

### Stream
- Connect (⌘R) / Disconnect (⌘.)
- Reload (⇧⌘R)
- Copy URL (⌘⇧C)
- Paste URL (⌘V — when toolbar URL field is focused)

### View
- Standard Window (⌘1)
- Enter Full Screen (⌃⌘F)
- Mini Player (⌘2)
- Toggle Status Overlay (⌘I)

### Window / Help — standard macOS items.

## Keyboard Shortcuts (summary)

| Shortcut | Action |
|---|---|
| ⌘R | Connect / Reconnect |
| ⌘. | Disconnect |
| ⌃⌘F | Toggle full screen |
| ⌘1 | Standard window |
| ⌘2 | Mini player |
| ⌘, | Preferences |
| Esc | Exit full screen |

## Visual Design

- System fonts only (`.body`, `.caption`).
- Adopts system Light/Dark appearance automatically.
- App icon: a single eye glyph composed with a rounded square camera silhouette; provided as an `.icns` with all required sizes.
- No app-specific accent color — uses the user's system accent.

## Empty / Error States

- First launch with no URL: standard window shows a centered call-to-action (`Add an RTSP URL to get started`) with a button that focuses the toolbar URL field.
- Persistent failure (e.g., DNS resolution fails repeatedly): after 5 failed reconnects the overlay switches to `Disconnected — <reason>` with a manual `Retry` button; backoff continues silently in the background.

## Accessibility

- All interactive elements have accessibility labels.
- Status overlay text honors Dynamic Type.
- Full keyboard navigability for the toolbar and preferences.
- Reduce Motion: disable overlay fade animations when the system setting is on.
