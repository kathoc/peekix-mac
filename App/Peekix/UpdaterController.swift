import SwiftUI
import Sparkle

@MainActor
final class UpdaterController: ObservableObject {
    let updater: SPUStandardUpdaterController

    init() {
        updater = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    func checkForUpdates() {
        updater.checkForUpdates(nil)
    }
}
