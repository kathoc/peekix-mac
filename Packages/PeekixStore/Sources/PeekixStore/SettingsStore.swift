import Foundation

@MainActor
public final class SettingsStore: ObservableObject {
    private let defaults: UserDefaults
    private static let lastURLKey = "lastURL"

    @Published public var lastURL: String {
        didSet { defaults.set(lastURL, forKey: Self.lastURLKey) }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.lastURL = defaults.string(forKey: Self.lastURLKey) ?? ""
    }
}
