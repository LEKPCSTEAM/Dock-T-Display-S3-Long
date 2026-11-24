import Foundation

public struct ReconnectPolicy: Sendable {
    private var attempt = 0
    private static let delays: [TimeInterval] = [1, 2, 4, 8, 15]

    public init() {}

    public mutating func nextDelay() -> TimeInterval {
        let delay = Self.delays[min(attempt, Self.delays.count - 1)]
        attempt += 1
        return delay
    }

    public mutating func reset() {
        attempt = 0
    }
}
