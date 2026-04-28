import SwiftUI

@main
struct PeekixApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var updaterController = UpdaterController()

    var body: some Scene {
        WindowGroup("Peekix") {
            ContentView()
                .frame(minWidth: 480, minHeight: 270)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .saveItem) {}
            CommandGroup(replacing: .printItem) {}
            CommandGroup(replacing: .textEditing) {}
            CommandGroup(replacing: .textFormatting) {}
            CommandGroup(replacing: .toolbar) {}
            CommandGroup(replacing: .sidebar) {}
            CommandGroup(replacing: .help) {}
            CommandGroup(after: .appInfo) {
                Button("アップデートを確認…") {
                    updaterController.checkForUpdates()
                }
            }
        }

        Settings {
            PreferencesView()
        }
    }
}
