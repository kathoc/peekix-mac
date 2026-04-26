import AppKit
import CoreGraphics
import os

/// Observes signals indicating the user is no longer looking at the screen so
/// playback can be torn down — keeping the camera's RTSP session list clean
/// (Eufy battery cameras share a single internal encoder across clients; a
/// half-open session destabilizes the stream for *other* viewers).
@MainActor
final class PowerStateObserver {
    enum Reason: String, Hashable, CustomStringConvertible {
        case systemSleep
        case screenLocked
        case screensaver
        case displaySleep
        case occluded

        var description: String { rawValue }
    }

    var onPause: ((Reason) -> Void)?
    var onResume: ((Reason) -> Void)?

    private(set) var reasons: Set<Reason> = []
    private let logger = Logger(subsystem: "app.peekix.mac", category: "PowerState")
    private var displayPollTimer: Timer?
    private var lastDisplayAsleep = false

    init() {
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(self, selector: #selector(systemWillSleep(_:)),
                       name: NSWorkspace.willSleepNotification, object: nil)
        ws.addObserver(self, selector: #selector(systemDidWake(_:)),
                       name: NSWorkspace.didWakeNotification, object: nil)

        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(self, selector: #selector(screenDidLock(_:)),
                        name: Notification.Name("com.apple.screenIsLocked"), object: nil)
        dnc.addObserver(self, selector: #selector(screenDidUnlock(_:)),
                        name: Notification.Name("com.apple.screenIsUnlocked"), object: nil)
        dnc.addObserver(self, selector: #selector(screensaverDidStart(_:)),
                        name: Notification.Name("com.apple.screensaver.didstart"), object: nil)
        dnc.addObserver(self, selector: #selector(screensaverDidStop(_:)),
                        name: Notification.Name("com.apple.screensaver.didstop"), object: nil)

        startDisplayPoll()
    }

    deinit {
        displayPollTimer?.invalidate()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
    }

    /// Forwarded from the window's occlusion state observer.
    func setOccluded(_ isOccluded: Bool) {
        if isOccluded { add(.occluded) } else { remove(.occluded) }
    }

    private func add(_ r: Reason) {
        let wasEmpty = reasons.isEmpty
        let isNew = !reasons.contains(r)
        if isNew { reasons.insert(r) }
        if isNew {
            logger.info("pause reason added: \(r.rawValue, privacy: .public) total=\(self.reasons.count, privacy: .public)")
        }
        // System sleep always re-triggers onPause so callers can perform a
        // synchronous teardown before the OS suspends, even if another reason
        // has already paused us.
        if wasEmpty || r == .systemSleep {
            onPause?(r)
        }
    }

    private func remove(_ r: Reason) {
        guard reasons.contains(r) else { return }
        reasons.remove(r)
        logger.info("pause reason removed: \(r.rawValue, privacy: .public) total=\(self.reasons.count, privacy: .public)")
        if reasons.isEmpty {
            onResume?(r)
        }
    }

    @objc private func systemWillSleep(_ n: Notification) { add(.systemSleep) }
    @objc private func systemDidWake(_ n: Notification) { remove(.systemSleep) }
    @objc private func screenDidLock(_ n: Notification) { add(.screenLocked) }
    @objc private func screenDidUnlock(_ n: Notification) { remove(.screenLocked) }
    @objc private func screensaverDidStart(_ n: Notification) { add(.screensaver) }
    @objc private func screensaverDidStop(_ n: Notification) { remove(.screensaver) }

    // No public macOS notification fires for "display asleep but system awake"
    // (e.g. external monitor powered off, or display-sleep idle timer < lock
    // timer). Polling CGDisplayIsAsleep every 10s is cheap and reliable.
    private func startDisplayPoll() {
        let timer = Timer(timeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.pollDisplay() }
        }
        RunLoop.main.add(timer, forMode: .common)
        displayPollTimer = timer
    }

    private func pollDisplay() {
        let asleep = CGDisplayIsAsleep(CGMainDisplayID()) != 0
        guard asleep != lastDisplayAsleep else { return }
        lastDisplayAsleep = asleep
        if asleep { add(.displaySleep) } else { remove(.displaySleep) }
    }
}
