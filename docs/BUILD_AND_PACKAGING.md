# Build and Packaging

This document defines how to produce a signed, notarized, single-file `.app` (and optional `.dmg`) that runs on a clean Apple Silicon macOS install with no external dependencies.

## Prerequisites (developer machine only)

- macOS 14+ on Apple Silicon
- Xcode 15.3 or later
- Apple Developer Program membership
- Developer ID Application certificate installed in the login keychain
- App-specific password for `notarytool` (stored via `xcrun notarytool store-credentials`)

The end user needs none of the above.

## Repository Layout

```
peekix-mac/
├── App/                          # Xcode app target
│   ├── Peekix.xcodeproj
│   ├── Peekix/                   # Swift sources, Assets.xcassets, Info.plist
│   └── Peekix.entitlements
├── Packages/
│   ├── PeekixCore/
│   ├── PeekixSession/
│   ├── PeekixUI/
│   └── PeekixStore/
├── Vendor/
│   └── ffmpeg/                   # arm64 static libs + headers (checked in or built locally)
│       ├── include/
│       └── lib/                  # libavformat.a, libavcodec.a, libavutil.a, libswscale.a, libswresample.a
├── Scripts/
│   ├── build-ffmpeg.sh           # one-shot: builds minimal arm64 FFmpeg into Vendor/ffmpeg
│   ├── archive.sh                # xcodebuild archive + export
│   ├── notarize.sh               # submit + staple
│   └── make-dmg.sh               # create-dmg invocation (or hdiutil fallback)
└── docs/
```

## FFmpeg Build (one-time, cached in `Vendor/ffmpeg/`)

`Scripts/build-ffmpeg.sh` runs the canonical FFmpeg `configure` with a minimal feature set:

```
./configure \
  --prefix="$PREFIX" \
  --arch=arm64 --target-os=darwin \
  --enable-cross-compile --cc=clang \
  --enable-static --disable-shared \
  --disable-programs --disable-doc --disable-htmlpages --disable-manpages \
  --disable-everything \
  --enable-protocol=file,tcp,udp,rtp,rtsp \
  --enable-demuxer=rtsp,rtp,h264,hevc,mpegts \
  --enable-parser=h264,hevc,aac \
  --enable-decoder=h264,hevc,aac \
  --enable-bsf=h264_mp4toannexb,hevc_mp4toannexb \
  --disable-network=0 \
  --disable-debug --enable-pic \
  --extra-cflags="-mmacosx-version-min=13.0 -arch arm64 -O2"
make -j$(sysctl -n hw.ncpu)
make install
```

Output static libs land in `Vendor/ffmpeg/lib/`. They are linked into `PeekixCore` via an SPM `systemLibrary`/binary-target wrapper. No dylibs ship inside the bundle.

## Xcode Project Settings

- **Architectures:** `arm64` only. Set `ARCHS = arm64`, `ONLY_ACTIVE_ARCH = NO` for Release. Remove `x86_64` from `VALID_ARCHS`.
- **Deployment target:** macOS 13.0.
- **Swift language mode:** Swift 5, strict concurrency = complete.
- **Hardened Runtime:** enabled.
- **App Sandbox:** enabled, with the entitlements:
  - `com.apple.security.network.client` (outgoing RTSP)
  - `com.apple.security.files.user-selected.read-only` (none required for v1, but reserved)
- **Info.plist:**
  - `LSMinimumSystemVersion` = `13.0`
  - `LSApplicationCategoryType` = `public.app-category.video`
  - `NSPrincipalClass` = `NSApplication`
  - `NSHighResolutionCapable` = `true`
- **Signing:** Developer ID Application certificate, manual signing.
- **Symbols:** `STRIP_INSTALLED_PRODUCT = YES`, `COPY_PHASE_STRIP = YES`, `DEBUG_INFORMATION_FORMAT = dwarf-with-dsym` (Release), upload dSYMs alongside the build artifacts.
- **Optimization:** `-O` for Swift, `-Os` for any C/Obj-C. LTO on for Release.

## Linking FFmpeg Statically

- The static libs are linked via `OTHER_LDFLAGS` in `PeekixCore` only.
- System frameworks linked alongside: `VideoToolbox`, `CoreMedia`, `CoreVideo`, `AudioToolbox`, `Metal`, `MetalKit`, `Network`, `Security`, `AppKit`.
- Verify there are no dynamic FFmpeg links in the final binary: `otool -L Peekix.app/Contents/MacOS/Peekix` must show only Apple-shipped dylibs.

## Building

```sh
# 1. (once) Build FFmpeg
./Scripts/build-ffmpeg.sh

# 2. Archive
xcodebuild \
  -project App/Peekix.xcodeproj \
  -scheme Peekix \
  -configuration Release \
  -destination 'generic/platform=macOS,arch=arm64' \
  -archivePath build/Peekix.xcarchive \
  archive

# 3. Export the .app
xcodebuild \
  -exportArchive \
  -archivePath build/Peekix.xcarchive \
  -exportPath build/export \
  -exportOptionsPlist Scripts/exportOptions.plist
```

`exportOptions.plist` selects `developer-id` distribution and disables the Mac App Store path.

## Code Signing

The export step signs everything. To verify:

```sh
codesign --verify --deep --strict --verbose=2 build/export/Peekix.app
spctl --assess --type execute --verbose build/export/Peekix.app
```

Both commands must pass before notarization.

## Notarization

```sh
ditto -c -k --keepParent build/export/Peekix.app build/Peekix.zip

xcrun notarytool submit build/Peekix.zip \
  --keychain-profile "peekix-notary" \
  --wait

xcrun stapler staple build/export/Peekix.app
xcrun stapler validate build/export/Peekix.app
```

## DMG (optional)

```sh
./Scripts/make-dmg.sh build/export/Peekix.app build/Peekix.dmg
codesign --sign "Developer ID Application: …" build/Peekix.dmg
xcrun notarytool submit build/Peekix.dmg --keychain-profile "peekix-notary" --wait
xcrun stapler staple build/Peekix.dmg
```

## Clean-Machine Smoke Test

This is the test that proves the "no dependencies" claim:

1. On a fresh macOS VM (or a Mac that has never had Xcode, Homebrew, or VLC installed) with the same major macOS version as the deployment target, copy the `.dmg` over.
2. Open the DMG, drag `Peekix.app` to `/Applications`.
3. Launch from Launchpad. Gatekeeper must accept it without showing an "unidentified developer" prompt.
4. Paste a known-good RTSP URL. Video must appear within the cold-launch SLA defined in `REQUIREMENTS.md`.
5. Quit and relaunch — the stream must auto-connect.
6. Disconnect Wi-Fi for 30 s, reconnect — the stream must come back without user action.
7. `otool -L` on the binary inside `/Applications/Peekix.app/Contents/MacOS/Peekix` must show **no** non-Apple dylibs.

If any of these fail, the build is not shippable.

## CI Notes

- A GitHub Actions runner with `macos-14-arm64` (or self-hosted Apple Silicon) handles the archive + notarization steps.
- Secrets required: signing certificate `.p12` and password, `notarytool` credentials, app-specific password.
- The FFmpeg artifacts in `Vendor/ffmpeg/` can be cached or re-built per CI run; rebuild takes a few minutes and produces a deterministic output for a pinned FFmpeg tag.

## Versioning

- Marketing version: semantic (`1.0.0`).
- Build number: monotonic integer, set by CI.
- Both written into `Info.plist` at build time.
