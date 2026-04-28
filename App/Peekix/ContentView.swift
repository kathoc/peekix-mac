import AppKit
import PeekixUI
import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = PlaybackViewModel()
    @State private var mouseActiveAt: Date = .distantPast
    @State private var hideTask: Task<Void, Never>?
    @State private var autoHideTick: Int = 0

    private static let controlBarAutoHideInterval: TimeInterval = 5

    var body: some View {
        GeometryReader { _ in
            let visible = controlBarVisible
            ZStack(alignment: .bottom) {
                VideoViewRepresentable(viewModel: viewModel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if let msg = viewModel.lastScreenshotMessage {
                    VStack {
                        Text(msg)
                            .font(.callout)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.65))
                            .foregroundColor(.white)
                            .cornerRadius(6)
                            .padding(.top, 12)
                        Spacer(minLength: 0)
                    }
                    .transition(.opacity)
                }
                // Control bar overlays the video; faded out when not hovered.
                // Kept in the view tree (not removed) so NSHostingView's
                // subview hierarchy stays stable across fullscreen transitions.
                controlBar
                    .opacity(visible ? 1 : 0)
                    .allowsHitTesting(visible)
                    .animation(.easeInOut(duration: 0.15), value: visible)
                if viewModel.windowMode != .mini {
                    persistentStatusDot
                        .allowsHitTesting(false)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        // Match the dot's in-bar position exactly so it doesn't
                        // shift when the bar fades in/out:
                        //   trailing = outerHorizontalPadding(12) + innerHorizontalPadding(12) = 24
                        //   bottom   = outerBottomPadding(12) + (barInnerHeight - dot)/2
                        //            = 12 + (30 - 8)/2 = 23
                        // (barInnerHeight = innerVerticalPadding(6)*2 + iconHeight(18) = 30)
                        .padding(.trailing, 24)
                        .padding(.bottom, 23)
                }
            }
            .background(Color.black.ignoresSafeArea())
            .background(WindowAccessor { window in
                viewModel.setWindow(window)
            })
            .background(keyboardShortcuts)
            .onHover { hovering in
                viewModel.isMouseHovering = hovering
                if hovering {
                    noteMouseActivity()
                } else {
                    cancelAutoHide()
                }
            }
            .onContinuousHover { phase in
                switch phase {
                case .active:
                    noteMouseActivity()
                case .ended:
                    cancelAutoHide()
                }
            }
            .onAppear { viewModel.startIfNeeded() }
        }
    }

    private func noteMouseActivity() {
        mouseActiveAt = Date()
        autoHideTick &+= 1
        viewModel.notePixelShiftMouseActivity()
        hideTask?.cancel()
        let interval = Self.controlBarAutoHideInterval
        hideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            guard !Task.isCancelled else { return }
            autoHideTick &+= 1
        }
    }

    private func cancelAutoHide() {
        hideTask?.cancel()
        hideTask = nil
        mouseActiveAt = .distantPast
        autoHideTick &+= 1
    }

    private var controlBarVisible: Bool {
        guard viewModel.windowMode != .mini else { return false }
        guard viewModel.isMouseHovering else { return false }
        _ = autoHideTick
        return Date().timeIntervalSince(mouseActiveAt) < Self.controlBarAutoHideInterval
    }

    private var persistentStatusDot: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 8, height: 8)
            .shadow(color: .black.opacity(0.6), radius: 1.5, x: 0, y: 0)
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

            if let err = viewModel.errorMessage {
                Text(err)
                    .foregroundColor(.red)
                    .lineLimit(1)
                    .font(.caption)
                    // Reserve space for the persistent status dot at the right edge.
                    .padding(.trailing, 14)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
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
