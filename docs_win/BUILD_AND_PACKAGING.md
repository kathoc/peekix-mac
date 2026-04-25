# Build and Packaging

## Goal

The distributed Windows build should run on a clean Windows machine without asking the user to install media runtimes separately.

## Windows target

Initial target:

```text
win-x64
```

Consider ARM64 later only if needed.

## .NET publish direction

Use self-contained publishing where practical so the user does not need to install the .NET runtime.

Example direction:

```powershell
dotnet publish .\src\Peekix.App\Peekix.App.csproj -c Release -r win-x64 --self-contained true
```

If single-file publishing causes issues with native media libraries, prefer a clean app folder or installer over forcing a single physical file.

The priority is “works reliably on a clean machine,” not “literally one file at all costs.”

## Native media components

If using LibVLCSharp, include the required native LibVLC package/components for Windows.

Do not rely on a system-installed VLC.

## Installer

For the first MVP, a portable folder build is acceptable if it is reliable.

Later, add an installer such as:

- MSIX
- WiX
- Inno Setup
- Squirrel/Velopack or similar

## macOS later

macOS packaging should produce an Apple Silicon `.app`.

Document:

- Build command
- App bundle structure
- Native media library bundling
- Code signing
- Notarization

Do not block Windows MVP on macOS packaging.

## Packaging acceptance test

Test on a clean Windows VM or a Windows Sandbox:

1. Install nothing manually.
2. Copy or install Peekix.
3. Launch Peekix.
4. Enter RTSP URL.
5. Confirm video playback.
6. Sleep/wake or network toggle.
7. Confirm automatic reconnect.
