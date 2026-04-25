import SwiftUI
import AppKit
import PeekixUI

struct ContentView: NSViewRepresentable {
    func makeNSView(context: Context) -> VideoView { VideoView() }
    func updateNSView(_ nsView: VideoView, context: Context) {}
}
