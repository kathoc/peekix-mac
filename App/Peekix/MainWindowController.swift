import AppKit
import PeekixUI

final class MainWindowController: NSWindowController {
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
    }

    private func setupToolbar() {
        let toolbar = NSToolbar(identifier: "MainToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        window?.toolbar = toolbar
    }

    private func setupVideoView() {
        guard let window = window else { return }
        let videoView = VideoView()
        window.contentView = videoView
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
            return item
        default:
            return nil
        }
    }
}

extension NSToolbarItem.Identifier {
    static let urlField = NSToolbarItem.Identifier("urlField")
    static let connectButton = NSToolbarItem.Identifier("connectButton")
    static let statusDot = NSToolbarItem.Identifier("statusDot")
}
