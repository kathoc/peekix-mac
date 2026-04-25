import SwiftUI
import PeekixStore

struct PreferencesView: View {
    @StateObject private var settings = SettingsStore()

    var body: some View {
        Form {
            Section("Stream") {
                TextField("RTSP URL", text: $settings.lastURL)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .padding()
        .frame(width: 400)
    }
}
