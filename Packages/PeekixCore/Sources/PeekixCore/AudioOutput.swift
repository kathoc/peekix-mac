import AVFoundation
import Foundation
import os

/// Owns the AVAudioEngine + player-node pipeline used to render decoded PCM
/// produced by `PlaybackEngine`. All AVAudioEngine state is mutated on a
/// dedicated serial queue, so calls from the demux thread, the main thread,
/// and any future reconnection path serialize cleanly without racing.
final class AudioOutput: @unchecked Sendable {
    private let queue = DispatchQueue(label: "app.peekix.mac.audio", qos: .userInteractive)
    private let logger = Logger(subsystem: "app.peekix.mac", category: "AudioOutput")

    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var format: AVAudioFormat?

    private let mutedLock = NSLock()
    private var _muted: Bool = false

    /// Snapshot of the current mute flag — safe to read from any thread.
    var isMuted: Bool {
        mutedLock.lock(); defer { mutedLock.unlock() }
        return _muted
    }

    func setMuted(_ muted: Bool) {
        mutedLock.lock(); _muted = muted; mutedLock.unlock()
        queue.async { [weak self] in
            guard let self, let p = self.player else { return }
            // Volume change is non-blocking; node keeps decoding so unmute is
            // immediate and there is no audible re-sync glitch.
            p.volume = muted ? 0 : 1
        }
    }

    /// Tears down any prior pipeline and constructs a fresh AVAudioEngine for
    /// the supplied source format. Safe to call from any thread; the actual
    /// AVAudioEngine work runs on the audio queue.
    func configure(sampleRate: Double, channels: Int) {
        let chCount = AVAudioChannelCount(max(1, min(2, channels)))
        let muted = isMuted
        queue.async { [weak self] in
            guard let self else { return }
            self.teardownLocked()
            guard let fmt = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: chCount) else {
                self.logger.error("AVAudioFormat init failed sr=\(Int(sampleRate), privacy: .public) ch=\(Int(chCount), privacy: .public)")
                return
            }
            let engine = AVAudioEngine()
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: fmt)
            // Touching mainMixerNode ensures the implicit graph wiring is
            // realized before start; AVAudioEngine otherwise lazy-initializes
            // and start() can fail with "required condition is false: _engine".
            engine.prepare()
            do {
                try engine.start()
            } catch {
                self.logger.error("AVAudioEngine.start failed: \(String(describing: error), privacy: .public)")
                return
            }
            player.volume = muted ? 0 : 1
            player.play()
            self.engine = engine
            self.player = player
            self.format = fmt
            self.logger.info("audio engine started sr=\(Int(sampleRate), privacy: .public) ch=\(Int(chCount), privacy: .public)")
        }
    }

    func enqueue(_ buffer: AVAudioPCMBuffer) {
        queue.async { [weak self] in
            guard let self, let p = self.player else { return }
            p.scheduleBuffer(buffer, completionHandler: nil)
        }
    }

    func teardown() {
        queue.async { [weak self] in
            self?.teardownLocked()
        }
    }

    /// Synchronous teardown: blocks until the audio queue drains. Intended for
    /// engine shutdown paths where we must guarantee the AVAudioEngine has
    /// stopped before the surrounding Swift state is torn down.
    func teardownSync() {
        queue.sync { [weak self] in
            self?.teardownLocked()
        }
    }

    /// Must be invoked from `queue`.
    private func teardownLocked() {
        if let p = player {
            p.stop()
        }
        if let e = engine {
            e.stop()
        }
        player = nil
        engine = nil
        format = nil
    }

    /// The output format negotiated for the current pipeline (planar Float32).
    /// Returned synchronously off the audio queue for use by the demux thread.
    func currentFormat() -> AVAudioFormat? {
        queue.sync { format }
    }
}
