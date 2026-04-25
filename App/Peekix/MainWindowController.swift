import AppKit
import CoreMedia
import CoreVideo
import PeekixCore
import PeekixUI
import os

final class MainWindowController: NSWindowController {
    private let logger = Logger(subsystem: "app.peekix.mac", category: "MainWindow")
    private var engine: PlaybackEngine?
    private var renderer: MetalRenderer?
    private weak var statusDotView: NSView?
    private var videoView: VideoView?

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 540),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .unifiedTitleAndToolbar],
            backing: .buffered,
            defer: false
        )
        window.title = "Peekix"
        window.minSize = NSSize(width: 480, height: 270)
        window.titlebarAppearsTransparent = false
        window.toolbarStyle = .unifiedCompact
        self.init(window: window)
        setupToolbar()
        setupVideoView()
        setupPlayback()
    }

    private func setupToolbar() {
        let toolbar = NSToolbar(identifier: "MainToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        window?.toolbar = toolbar
    }

    private func setupVideoView() {
        guard let window = window else { return }
        let view = VideoView()
        window.contentView = view
        videoView = view
    }

    private func setupPlayback() {
        guard let videoView else { return }
        guard let renderer = MetalRenderer() else {
            logger.error("MetalRenderer init failed")
            return
        }
        renderer.attach(to: videoView.metalLayer)
        let engine = PlaybackEngine()
        engine.metalRenderer = renderer
        engine.delegate = self
        self.renderer = renderer
        self.engine = engine
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        startHardcodedStream()
    }

    private func startHardcodedStream() {
        // TODO: replace with the user's RTSP URL from settings (P1).
        guard let url = URL(string: "rtsp://192.168.1.1/stream1") else { return }
        logger.info("starting hardcoded stream \(url.absoluteString, privacy: .public)")
        engine?.start(url: url, transport: .tcp)
    }

    private func setStatusDotColor(_ color: NSColor) {
        statusDotView?.layer?.backgroundColor = color.cgColor
    }
}

extension MainWindowController: NSToolbarDelegate {
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.urlField, .connectButton, .statusDot]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.urlField, .connectButton, .statusDot, .flexibleSpace]
    }

    func toolbar(_ toolbar: NSToolbar,
                 itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch itemIdentifier {
        case .urlField:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            let field = NSTextField()
            field.placeholderString = "rtsp://user:pass@host/stream"
            field.frame = NSRect(x: 0, y: 0, width: 400, height: 22)
            item.view = field
            item.label = "URL"
            return item
        case .connectButton:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            let button = NSButton(title: "Connect", target: nil, action: nil)
            item.view = button
            item.label = "Connect"
            return item
        case .statusDot:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            let dot = NSView(frame: NSRect(x: 0, y: 0, width: 12, height: 12))
            dot.wantsLayer = true
            dot.layer?.backgroundColor = NSColor.systemGray.cgColor
            dot.layer?.cornerRadius = 6
            item.view = dot
            item.label = "Status"
            statusDotView = dot
            return item
        default:
            return nil
        }
    }
}

extension MainWindowController: PlaybackEngineDelegate {
    func playbackEngine(_ engine: PlaybackEngine, didOutputFrame pixelBuffer: CVPixelBuffer, pts: CMTime) {
        // Renderer is invoked directly by the engine; nothing to do here.
    }

    func playbackEngine(_ engine: PlaybackEngine, didChangeStatus status: PlaybackEngineStatus) {
        let color: NSColor
        switch status {
        case .idle, .stopped:
            color = .systemGray
        case .connecting:
            color = .systemYellow
        case .playing:
            color = .systemGreen
        }
        setStatusDotColor(color)
    }

    func playbackEngine(_ engine: PlaybackEngine, didEncounterError error: Error) {
        logger.error("playback error: \(String(describing: error), privacy: .public)")
        setStatusDotColor(.systemRed)
    }
}

extension NSToolbarItem.Identifier {
    static let urlField = NSToolbarItem.Identifier("urlField")
    static let connectButton = NSToolbarItem.Identifier("connectButton")
    static let statusDot = NSToolbarItem.Identifier("statusDot")
}
