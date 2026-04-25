import SwiftUI

@main
struct PeekixApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup("Peekix") {
            ContentView()
                .frame(minWidth: 480, minHeight: 270)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        Settings {
            PreferencesView()
        }
    }
}
