import AppKit
import Combine
import CoreMedia
import CoreVideo
import Foundation
import PeekixCore
import PeekixUI

enum WindowMode {
    case normal, fullscreen, mini
}

@MainActor
final class PlaybackViewModel: NSObject, ObservableObject, PlaybackEngineDelegate, NSWindowDelegate {
    @Published var status: PlaybackEngineStatus = .idle
    @Published var errorMessage: String?
    @Published var videoAspect: CGFloat? = nil {
        didSet { applyWindowAspect() }
    }
    @Published var isMuted: Bool = false
    @Published var isAlwaysOnTop: Bool = false
    @Published var windowMode: WindowMode = .normal

    private let engine = PlaybackEngine()
    private var renderer: MetalRenderer?
    private weak var window: NSWindow?
    private weak var attachedView: VideoView?

    private var savedNormalStyleMask: NSWindow.StyleMask?
    private var savedFullscreenFrame: NSRect?

    private var isTransitioning: Bool = false
    // True between the moment we *schedule* a toggleFullScreen and the moment
    // AppKit actually starts the transition (windowWillEnter/Exit fires). The
    // schedule itself is async (see setMode) to keep SwiftUI's event tick from
    // overlapping AppKit's exit transition, which crashes inside
    // _adjustNeedsDisplayRegionForNewFrame when the view tree is mid-update.
    private var pendingToggle: Bool = false
    private var lastTransitionEndedAt: CFAbsoluteTime = 0
    private static let postTransitionCooldown: CFTimeInterval = 0.2

    // Stress-test continuations (used by PEEKIX_FS_STRESS harness only).
    private var enterFSContinuation: CheckedContinuation<Void, Never>?
    private var exitFSContinuation: CheckedContinuation<Void, Never>?

    private var zoomScale: Float = 1.0
    private var zoomOffset: SIMD2<Float> = SIMD2<Float>(0, 0)

    private static let urlKey = "rtspURL"
    private static let defaultURL = "rtsp://user:pass@host/stream"

    private var resolvedURL: URL? {
        let s = UserDefaults.standard.string(forKey: Self.urlKey).flatMap { $0.isEmpty ? nil : $0 }
            ?? ProcessInfo.processInfo.environment["PEEKIX_RTSP_URL"]
            ?? Self.defaultURL
        return URL(string: s)
    }

    override init() {
        super.init()
        engine.delegate = self
    }

    var isPlaying: Bool {
        switch status {
        case .playing, .connecting: return true
        case .idle, .stopped: return false
        }
    }

    func attach(videoView: VideoView) {
        attachedView = videoView
        if renderer == nil, let r = MetalRenderer() {
            r.attach(to: videoView.metalLayer)
            r.onVideoSizeChange = { [weak self] size in
                guard let self else { return }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if size.height > 0 {
                        self.videoAspect = size.width / size.height
                    }
                }
            }
            renderer = r
            engine.metalRenderer = r
        } else if let r = renderer {
            // SwiftUI may rebuild the NSViewRepresentable across major view-tree
            // changes (e.g., the control-bar appearing/disappearing on fullscreen
            // transitions). Re-bind the renderer to the *current* CAMetalLayer so it
            // never writes into a detached/dealloc'd layer from the render thread.
            r.attach(to: videoView.metalLayer)
        }
        videoView.onScroll = { [weak self] deltaY, point, size in
            guard let self else { return }
            self.handleScroll(deltaY: deltaY, point: point, size: size)
        }
        videoView.onDoubleClick = { [weak self] in
            guard let self else { return }
            self.resetZoom()
        }
    }

    func setWindow(_ window: NSWindow?) {
        guard let window, self.window !== window else { return }
        self.window = window
        window.delegate = self
        // Allow native fullscreen via the green button and Cmd+Ctrl+F.
        var collection = window.collectionBehavior
        collection.insert(.fullScreenPrimary)
        window.collectionBehavior = collection
        applyAlwaysOnTop()
        applyWindowAspect()

        if let raw = ProcessInfo.processInfo.environment["PEEKIX_FS_STRESS"],
           let n = Int(raw), n > 0 {
            Task { @MainActor [weak self] in
                await self?.runFullscreenStress(cycles: n)
            }
        }

        if ProcessInfo.processInfo.environment["PEEKIX_START_MINI"] == "1" {
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 300_000_000)
                self?.toggleMiniMode()
            }
        }
    }

    private func runFullscreenStress(cycles: Int) async {
        FileHandle.standardError.write(Data("[FS_STRESS] task entered\n".utf8))
        // Give the window a moment to settle and SwiftUI to finish initial layout.
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        guard let w = window else {
            FileHandle.standardError.write(Data("[FS_STRESS] FAIL: no window\n".utf8))
            exit(2)
        }
        let originalFrame = w.frame
        FileHandle.standardError.write(Data("[FS_STRESS] start cycles=\(cycles) frame=\(NSStringFromRect(originalFrame))\n".utf8))
        var maxDrift: CGFloat = 0
        for i in 1...cycles {
            // Enter fullscreen.
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                self.enterFSContinuation = c
                self.toggleFullscreen()
            }
            // Exit fullscreen.
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                self.exitFSContinuation = c
                self.toggleFullscreen()
            }
            let cur = w.frame
            let drift = max(
                abs(cur.origin.x - originalFrame.origin.x),
                abs(cur.origin.y - originalFrame.origin.y),
                abs(cur.size.width - originalFrame.size.width),
                abs(cur.size.height - originalFrame.size.height)
            )
            maxDrift = max(maxDrift, drift)
            FileHandle.standardError.write(Data("[FS_STRESS] cycle=\(i)/\(cycles) frame=\(NSStringFromRect(cur)) drift=\(drift)\n".utf8))
            // Brief settle to let AppKit complete any post-transition cleanup
            // (matches realistic human-paced toggling, ~4Hz).
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        FileHandle.standardError.write(Data("[FS_STRESS] PASS cycles=\(cycles) max_drift=\(maxDrift)\n".utf8))
        // Allow stdout to flush before terminating.
        try? await Task.sleep(nanoseconds: 200_000_000)
        NSApp.terminate(nil)
    }

    static let controlBarHeight: CGFloat = 44

    private func applyWindowAspect() {
        guard let w = window, let a = videoAspect, a > 0 else { return }
        // Skip while AppKit owns the window (during fullscreen transitions and
        // while the saved frame is being restored). Geometry mutations here race
        // with the animation and have crashed historically.
        if windowMode == .fullscreen || isTransitioning { return }
        if w.styleMask.contains(.fullScreen) { return }
        let controlBarH: CGFloat = windowMode == .mini ? 0 : Self.controlBarHeight
        var f = w.frame
        let chrome = f.size.height - w.contentLayoutRect.size.height
        guard chrome >= 0 else { return }
        let contentW = max(1, f.size.width)
        let videoH = (contentW / a).rounded()
        let newContentH = videoH + controlBarH
        let newFrameH = newContentH + chrome
        guard newFrameH > 0 else { return }
        f.origin.y += f.size.height - newFrameH
        f.size.height = newFrameH
        // We enforce the aspect ratio precisely in windowWillResize (a fixed
        // control-bar height makes a single contentAspectRatio incorrect), and
        // leaving contentAspectRatio set across a fullscreen transition has been
        // observed to fight AppKit's animator. Always clear it here.
        w.contentAspectRatio = .zero
        w.setFrame(f, display: true, animate: false)
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        // Hands-off during fullscreen transitions and while restoring the saved
        // frame on exit. AppKit drives the size; clobbering it here is what
        // produced the visible crash.
        if isTransitioning { return frameSize }
        guard let a = videoAspect, a > 0,
              windowMode != .fullscreen,
              !sender.styleMask.contains(.fullScreen)
        else {
            return frameSize
        }
        let chrome = sender.frame.size.height - sender.contentLayoutRect.size.height
        guard chrome >= 0 else { return frameSize }
        let contentW = max(1, frameSize.width)
        let videoH = (contentW / a).rounded()
        let controlBarH: CGFloat = windowMode == .mini ? 0 : Self.controlBarHeight
        let newFrameH = videoH + controlBarH + chrome
        guard newFrameH > 0 else { return frameSize }
        return NSSize(width: contentW, height: newFrameH)
    }

    func startIfNeeded() {
        if case .idle = status {
            play()
        }
    }

    func play() {
        guard let url = resolvedURL else {
            errorMessage = "invalid URL"
            return
        }
        errorMessage = nil
        engine.start(url: url, transport: .tcp)
    }

    func stop() {
        engine.stop()
    }

    func togglePlayPause() {
        if isPlaying { stop() } else { play() }
    }

    func toggleMute() {
        isMuted.toggle()
        if isMuted { engine.mute() } else { engine.unmute() }
    }

    func toggleAlwaysOnTop() {
        isAlwaysOnTop.toggle()
        applyAlwaysOnTop()
    }

    private func applyAlwaysOnTop() {
        guard let w = window else { return }
        // NEVER mutate window.level during or around a fullscreen transition,
        // and never apply .floating while the window is in/entering fullscreen.
        // A non-.normal level on a fullscreen-bound NSWindow has been observed
        // to corrupt AppKit's region bookkeeping during the exit transition
        // (crash inside _adjustNeedsDisplayRegionForNewFrame).
        if isTransitioning || pendingToggle { return }
        if w.styleMask.contains(.fullScreen) || windowMode == .fullscreen {
            w.level = .normal
            return
        }
        if windowMode == .mini {
            w.level = .floating
            return
        }
        w.level = isAlwaysOnTop ? .floating : .normal
    }

    func toggleMiniMode() {
        guard let w = window else { return }
        // Never modify styleMask while a fullscreen transition is in flight.
        if isTransitioning { return }
        if windowMode == .mini {
            if let saved = savedNormalStyleMask {
                w.styleMask = saved
            } else {
                w.styleMask.insert([.titled, .closable, .miniaturizable, .resizable])
                w.styleMask.remove(.borderless)
            }
            savedNormalStyleMask = nil
            w.isMovableByWindowBackground = false
            windowMode = .normal
            applyAlwaysOnTop()
            applyWindowAspect()
        } else {
            if windowMode == .fullscreen {
                setMode(.normal)
                return
            }
            savedNormalStyleMask = w.styleMask
            w.styleMask.remove([.titled, .closable, .miniaturizable, .resizable])
            w.styleMask.insert(.borderless)
            w.isMovableByWindowBackground = true
            w.level = .floating
            windowMode = .mini
        }
    }

    func toggleFullscreen() {
        // Re-entrancy guard: rapid presses (Cmd+Ctrl+F repeat, double-click on
        // the green button, or the "F" SwiftUI keyboardShortcut firing twice
        // before AppKit even starts the transition) must not stack.
        if isTransitioning || pendingToggle { return }
        let nowFS = window?.styleMask.contains(.fullScreen) == true
        setMode(nowFS ? .normal : .fullscreen)
    }

    func setMode(_ mode: WindowMode) {
        guard let w = window else { return }
        if isTransitioning || pendingToggle { return }
        let isFS = w.styleMask.contains(.fullScreen)
        if mode == .fullscreen {
            if !isFS {
                scheduleToggleFullScreen()
            } else {
                windowMode = .fullscreen
            }
            return
        }
        // mode == .normal
        if isFS {
            scheduleToggleFullScreen()
        } else if windowMode != .normal {
            windowMode = .normal
            applyAlwaysOnTop()
            applyWindowAspect()
        }
    }

    // The SwiftUI keyboardShortcut("f") Button action and the control-bar
    // Button action both run *inside* SwiftUI's event/update tick. Calling
    // NSWindow.toggleFullScreen synchronously from there starts AppKit's
    // _NSExitFullScreenTransitionController while SwiftUI is still mutating
    // the hosting view tree, and the controller's
    // _adjustNeedsDisplayRegionForNewFrame trips a brk 1 against the
    // mid-flight region. Hopping to the next runloop turn lets SwiftUI's tick
    // settle so AppKit owns a stable view tree for the entire transition.
    private func scheduleToggleFullScreen() {
        pendingToggle = true
        // Force a hard separation between the SwiftUI event/update tick that
        // produced this call and the AppKit fullscreen transition. A single
        // DispatchQueue.main.async hop is not enough — SwiftUI's Update
        // machinery (Update.dispatchActions) can still be unwinding state on
        // the next runloop turn, and AppKit's _NSExitFullScreenTransitionController
        // touches the host view tree synchronously inside
        // -setupWindowForAfterFullScreenExit, which crashes if the tree is
        // mid-mutation. Two strategies layered together:
        //   1) Pre-pin window.level to .normal so a .floating level cannot
        //      reach the FS state machine (a known cause of region corruption).
        //   2) Delay the actual toggleFullScreen far enough to be safely
        //      outside any in-flight SwiftUI update / Combine publisher chain.
        //      ~50ms is conservative and not user-visible.
        if let w = window, !w.styleMask.contains(.fullScreen) {
            w.level = .normal
        }
        let now = CFAbsoluteTimeGetCurrent()
        let cooldownRemaining = max(0, lastTransitionEndedAt + Self.postTransitionCooldown - now)
        let delay = max(0.05, cooldownRemaining)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, let w = self.window else {
                self?.pendingToggle = false
                return
            }
            self.pendingToggle = false
            CATransaction.flush()
            w.toggleFullScreen(nil)
        }
    }

    // MARK: - NSWindowDelegate (fullscreen lifecycle)

    func windowWillEnterFullScreen(_ notification: Notification) {
        isTransitioning = true
        renderer?.isSuspended = true
        if let w = window { savedFullscreenFrame = w.frame }
    }

    func customWindowsToExitFullScreen(for window: NSWindow) -> [NSWindow]? {
        return [window]
    }

    func window(_ window: NSWindow, startCustomAnimationToExitFullScreenWithDuration duration: TimeInterval) {
        guard let target = savedFullscreenFrame else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = duration
            window.animator().setFrame(target, display: true)
        }
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        isTransitioning = false
        lastTransitionEndedAt = CFAbsoluteTimeGetCurrent()
        renderer?.isSuspended = false
        windowMode = .fullscreen
        if let c = enterFSContinuation { enterFSContinuation = nil; c.resume() }
    }

    func windowDidFailToEnterFullScreen(_ window: NSWindow) {
        isTransitioning = false
        lastTransitionEndedAt = CFAbsoluteTimeGetCurrent()
        savedFullscreenFrame = nil
        renderer?.isSuspended = false
        windowMode = .normal
        applyWindowAspect()
    }

    func windowWillExitFullScreen(_ notification: Notification) {
        isTransitioning = true
        renderer?.isSuspended = true
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        isTransitioning = false
        lastTransitionEndedAt = CFAbsoluteTimeGetCurrent()
        savedFullscreenFrame = nil
        windowMode = .normal
        applyAlwaysOnTop()
        applyWindowAspect()
        renderer?.isSuspended = false
        if let c = exitFSContinuation { exitFSContinuation = nil; c.resume() }
    }

    func windowDidFailToExitFullScreen(_ window: NSWindow) {
        isTransitioning = false
        lastTransitionEndedAt = CFAbsoluteTimeGetCurrent()
        renderer?.isSuspended = false
        windowMode = .fullscreen
    }

    private func resetZoom() {
        zoomScale = 1.0
        zoomOffset = SIMD2<Float>(0, 0)
        renderer?.zoomScale = 1.0
        renderer?.zoomOffset = SIMD2<Float>(0, 0)
    }

    private func handleScroll(deltaY: CGFloat, point: NSPoint, size: NSSize) {
        guard size.width > 0, size.height > 0 else { return }
        // VideoView is flipped (top-left origin); texCoord (0,0) is top in our shader.
        let cursor = SIMD2<Float>(
            Float(max(0, min(1, point.x / size.width))),
            Float(max(0, min(1, point.y / size.height)))
        )
        let oldZoom = zoomScale
        let factor = Float(exp(deltaY * 0.02))
        let newZoom = max(1.0, min(8.0, oldZoom * factor))

        // tc = offset + (cursor - 0.5)/zoom + 0.5; keep tc fixed at cursor.
        let cursorMinusHalf = cursor - SIMD2<Float>(0.5, 0.5)
        var newOffset = zoomOffset + cursorMinusHalf * (1.0 / oldZoom - 1.0 / newZoom)
        let bound = max(0, 0.5 - 0.5 / newZoom)
        newOffset.x = max(-bound, min(bound, newOffset.x))
        newOffset.y = max(-bound, min(bound, newOffset.y))

        zoomScale = newZoom
        zoomOffset = newOffset
        renderer?.zoomScale = newZoom
        renderer?.zoomOffset = newOffset
    }

    nonisolated func playbackEngine(_ engine: PlaybackEngine, didOutputFrame pixelBuffer: CVPixelBuffer, pts: CMTime) {}

    nonisolated func playbackEngine(_ engine: PlaybackEngine, didChangeStatus status: PlaybackEngineStatus) {
        Task { @MainActor in self.status = status }
    }

    nonisolated func playbackEngine(_ engine: PlaybackEngine, didEncounterError error: Error) {
        let msg = String(describing: error)
        Task { @MainActor in self.errorMessage = msg }
    }
}
