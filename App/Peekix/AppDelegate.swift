import AppKit
import PeekixCore
import os

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: "app.peekix.mac", category: "App")

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("ffmpeg \(ffmpegVersionString(), privacy: .public)")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
