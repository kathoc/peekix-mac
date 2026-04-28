import AppKit
import PeekixCore
import os

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: "app.peekix.mac", category: "App")

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("ffmpeg \(ffmpegVersionString(), privacy: .public)")
        removeFormatMenu()
    }

    private func removeFormatMenu() {
        guard let mainMenu = NSApp.mainMenu else { return }
        if let formatItem = mainMenu.items.first(where: { $0.submenu?.title == "Format" || $0.title == "Format" || $0.submenu?.title == "フォーマット" || $0.title == "フォーマット" }) {
            mainMenu.removeItem(formatItem)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
