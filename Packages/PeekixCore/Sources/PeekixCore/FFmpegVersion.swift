import CFFmpeg
import Foundation

public func printFFmpegVersion() {
    let v = avformat_version()
    let major = (v >> 16) & 0xFF
    let minor = (v >> 8) & 0xFF
    let patch = v & 0xFF
    print("[PeekixCore] libavformat \(major).\(minor).\(patch)")
}

public func ffmpegVersionString() -> String {
    let v = avformat_version()
    let major = (v >> 16) & 0xFF
    let minor = (v >> 8) & 0xFF
    let patch = v & 0xFF
    return "\(major).\(minor).\(patch)"
}
