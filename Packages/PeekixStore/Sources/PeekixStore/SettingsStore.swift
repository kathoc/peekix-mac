import Foundation

@MainActor
public final class SettingsStore: ObservableObject {
    private let defaults: UserDefaults
    private static let lastURLKey = "lastURL"
    private static let screenshotBookmarkKey = "screenshotDirBookmark"

    @Published public var lastURL: String {
        didSet { defaults.set(lastURL, forKey: Self.lastURLKey) }
    }

    @Published public var screenshotDirectoryBookmark: Data? {
        didSet { defaults.set(screenshotDirectoryBookmark, forKey: Self.screenshotBookmarkKey) }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.lastURL = defaults.string(forKey: Self.lastURLKey) ?? ""
        self.screenshotDirectoryBookmark = defaults.data(forKey: Self.screenshotBookmarkKey)
    }

    /// Returns the user-configured screenshot directory if available, else the
    /// default `~/Pictures`. The returned URL is *not* yet security-scoped —
    /// use `withScreenshotDirectoryAccess` to perform writes.
    public var screenshotDirectoryDisplayURL: URL {
        if let data = currentScreenshotBookmark(),
           let url = try? resolveBookmark(data) {
            return url
        }
        return defaultPicturesURL
    }

    /// Always reads the bookmark fresh from UserDefaults so that changes made
    /// by another `SettingsStore` instance (e.g., the Preferences scene) are
    /// picked up by the playback scene without needing a notification bus.
    private func currentScreenshotBookmark() -> Data? {
        defaults.data(forKey: Self.screenshotBookmarkKey)
    }

    public var defaultPicturesURL: URL {
        FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Pictures")
    }

    /// Stores a security-scoped bookmark for the chosen directory. Pass nil to
    /// reset to the default `~/Pictures`.
    public func setScreenshotDirectory(_ url: URL?) throws {
        guard let url else {
            screenshotDirectoryBookmark = nil
            return
        }
        let data = try url.bookmarkData(options: [.withSecurityScope],
                                        includingResourceValuesForKeys: nil,
                                        relativeTo: nil)
        screenshotDirectoryBookmark = data
    }

    /// Resolves the configured directory and runs `body` while holding the
    /// security scope (if needed). Falls back to `~/Pictures` (which is
    /// covered by the `assets.pictures.read-write` entitlement).
    public func withScreenshotDirectoryAccess<T>(_ body: (URL) throws -> T) throws -> T {
        if let data = currentScreenshotBookmark() {
            let url = try resolveBookmark(data)
            let started = url.startAccessingSecurityScopedResource()
            defer { if started { url.stopAccessingSecurityScopedResource() } }
            return try body(url)
        }
        return try body(defaultPicturesURL)
    }

    private func resolveBookmark(_ data: Data) throws -> URL {
        var stale = false
        let url = try URL(resolvingBookmarkData: data,
                          options: [.withSecurityScope],
                          relativeTo: nil,
                          bookmarkDataIsStale: &stale)
        if stale {
            if let refreshed = try? url.bookmarkData(options: [.withSecurityScope],
                                                    includingResourceValuesForKeys: nil,
                                                    relativeTo: nil) {
                screenshotDirectoryBookmark = refreshed
            }
        }
        return url
    }
}
