import Foundation

public enum SessionStatus: Equatable, Sendable {
    case idle
    case connecting
    case playing
    case reconnecting(attempt: Int)
    case failed(reason: String)
}
