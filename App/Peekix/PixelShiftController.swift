import AppKit
import Foundation
import PeekixUI

// MiniLED burn-in mitigation. While the app is in fullscreen we slowly walk
// the rendered video by ±20px on both axes (triangle wave with phase-offset
// X/Y so the path is not a straight diagonal). The host CALayer masks to
// bounds so the shifted-out edge is hidden behind black, and the same shift
// keeps every fixed-luminance boundary moving across local-dimming zones.
//
// Mouse activity pauses advancement but does NOT reset position — the
// initial position would otherwise become the most-dwelled-on spot.
@MainActor
final class PixelShiftController {
    weak var videoView: VideoView?

    private var timer: Timer?
    private var step: Int = 0
    private var paused: Bool = false
    private var enabled: Bool = false

    private static let amplitudeX: Int = 20
    private static let amplitudeY: Int = 20
    private static let intervalSeconds: TimeInterval = 30
    // Out-of-phase Y offset so X and Y don't move in lockstep.
    private static let yPhaseOffset: Int = 13

    func setEnabled(_ on: Bool) {
        guard enabled != on else { return }
        enabled = on
        if on {
            startTimer()
            applyCurrent()
        } else {
            stopTimer()
            step = 0
            paused = false
            videoView?.pixelShift = .zero
        }
    }

    func setPaused(_ value: Bool) {
        paused = value
    }

    func attach(videoView: VideoView) {
        self.videoView = videoView
        if enabled { applyCurrent() }
    }

    private func startTimer() {
        stopTimer()
        let t = Timer(timeInterval: Self.intervalSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard enabled, !paused else { return }
        step &+= 1
        applyCurrent()
    }

    private func applyCurrent() {
        let x = Self.triangle(step, amplitude: Self.amplitudeX)
        let y = Self.triangle(step + Self.yPhaseOffset, amplitude: Self.amplitudeY)
        videoView?.pixelShift = CGPoint(x: x, y: y)
    }

    private static func triangle(_ p: Int, amplitude R: Int) -> Int {
        let period = 4 * R
        var m = p % period
        if m < 0 { m += period }
        if m <= R { return m }
        if m <= 3 * R { return 2 * R - m }
        return m - 4 * R
    }
}
