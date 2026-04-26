import AppKit
import SwiftUI
import PeekixStore

struct PreferencesView: View {
    @StateObject private var settings = SettingsStore()
    @State private var saveError: String?

    var body: some View {
        Form {
            Section("Stream") {
                TextField("RTSP URL", text: $settings.lastURL)
                    .textFieldStyle(.roundedBorder)
            }

            Section("スクリーンショット") {
                HStack {
                    Text("保存先:")
                    Text(settings.screenshotDirectoryDisplayURL.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                HStack {
                    Button("変更...") { chooseDirectory() }
                    Button("デフォルト (~/Pictures) に戻す") {
                        try? settings.setScreenshotDirectory(nil)
                    }
                    .disabled(settings.screenshotDirectoryBookmark == nil)
                    Spacer()
                }
                if let saveError {
                    Text(saveError).foregroundColor(.red).font(.caption)
                }
                Text("ショートカット: C で現在の映像を元の解像度のまま PNG 保存")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(width: 480)
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = settings.screenshotDirectoryDisplayURL
        panel.prompt = "選択"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try settings.setScreenshotDirectory(url)
                saveError = nil
            } catch {
                saveError = error.localizedDescription
            }
        }
    }
}
