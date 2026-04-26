import AppKit
import PeekixUI
import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = PlaybackViewModel()

    var body: some View {
        GeometryReader { geo in
            let visible = controlBarVisible(in: geo.size)
            VStack(spacing: 0) {
                ZStack(alignment: .top) {
                    VideoViewRepresentable(viewModel: viewModel)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if let msg = viewModel.lastScreenshotMessage {
                        Text(msg)
                            .font(.callout)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.65))
                            .foregroundColor(.white)
                            .cornerRadius(6)
                            .padding(.top, 12)
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Control bar is always present in the view tree to keep
                // NSHostingView's subview hierarchy stable across fullscreen
                // transitions. Mutating the tree (via `if`) between enter and
                // exit destabilizes AppKit's region bookkeeping and crashes
                // _adjustNeedsDisplayRegionForNewFrame on exit. We collapse it
                // to zero height + hidden when not visible.
                controlBar
                    .frame(height: visible ? PlaybackViewModel.controlBarHeight : 0)
                    .opacity(visible ? 1 : 0)
                    .allowsHitTesting(visible)
                    .clipped()
            }
            .background(Color.black.ignoresSafeArea())
            .background(WindowAccessor { window in
                viewModel.setWindow(window)
            })
            .background(keyboardShortcuts)
            .onAppear { viewModel.startIfNeeded() }
        }
    }


    private func controlBarVisible(in size: CGSize) -> Bool {
        switch viewModel.windowMode {
        case .mini:
            return false
        case .normal:
            return true
        case .fullscreen:
            // Show the control bar in the bottom letterbox area when the
            // screen is taller than the video's natural aspect (e.g. a 16:9
            // video on a 16:10 display) and there is at least controlBarHeight
            // of vertical slack below the video.
            guard let a = viewModel.videoAspect, a > 0,
                  size.width > 0, size.height > 0 else { return false }
            let videoH = size.width / a
            return size.height - videoH >= PlaybackViewModel.controlBarHeight
        }
    }

    private var controlBar: some View {
        HStack(spacing: 14) {
            Button(action: { viewModel.togglePlayPause() }) {
                Image(systemName: viewModel.isPlaying ? "stop.fill" : "play.fill")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.borderless)
            .help(viewModel.isPlaying ? "停止" : "接続")

            Button(action: { viewModel.toggleMute() }) {
                Image(systemName: viewModel.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.borderless)
            .help(viewModel.isMuted ? "ミュート中 (V)" : "音声あり (V)")

            Button(action: { viewModel.toggleAlwaysOnTop() }) {
                Image(systemName: viewModel.isAlwaysOnTop ? "pin.fill" : "pin")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.borderless)
            .help(viewModel.isAlwaysOnTop ? "最前面固定を解除" : "最前面に固定")

            Button(action: { viewModel.toggleFullscreen() }) {
                Image(systemName: "rectangle.expand.vertical")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.borderless)
            .help("フルスクリーン (F)")

            Button(action: { viewModel.captureScreenshot() }) {
                Image(systemName: "camera.fill")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.borderless)
            .help("画像を保存 (C)")

            Spacer()

            statusIndicator
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var statusIndicator: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            if let err = viewModel.errorMessage {
                Text(err)
                    .foregroundColor(.red)
                    .lineLimit(1)
                    .font(.caption)
            }
        }
    }

    private var statusColor: Color {
        switch viewModel.status {
        case .idle, .stopped: return .gray
        case .connecting: return .yellow
        case .playing: return .green
        }
    }

    private var keyboardShortcuts: some View {
        ZStack {
            Button("") { viewModel.toggleFullscreen() }
                .keyboardShortcut("f", modifiers: [])
            Button("") { viewModel.togglePlayPause() }
                .keyboardShortcut(.space, modifiers: [])
            Button("") { viewModel.toggleMute() }
                .keyboardShortcut("v", modifiers: [])
            Button("") { viewModel.toggleMiniMode() }
                .keyboardShortcut("m", modifiers: [])
            Button("") { viewModel.captureScreenshot() }
                .keyboardShortcut("c", modifiers: [])
            Button("") { viewModel.toggleAlwaysOnTop() }
                .keyboardShortcut("t", modifiers: [])
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .allowsHitTesting(false)
    }
}

private struct VideoViewRepresentable: NSViewRepresentable {
    let viewModel: PlaybackViewModel

    func makeNSView(context: Context) -> VideoView {
        let v = VideoView()
        viewModel.attach(videoView: v)
        return v
    }

    func updateNSView(_ nsView: VideoView, context: Context) {}
}

private struct WindowAccessor: NSViewRepresentable {
    var onWindow: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { [weak v] in
            onWindow(v?.window)
        }
        return v
    }

    func updateNSView(_ v: NSView, context: Context) {
        DispatchQueue.main.async { [weak v] in
            onWindow(v?.window)
        }
    }
}
