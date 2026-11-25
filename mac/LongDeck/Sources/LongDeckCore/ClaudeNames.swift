import Foundation

public final class ClaudeNames: @unchecked Sendable {
    public static let cacheTTL: TimeInterval = 30

    private let runner: TmuxRunner
    private let lock = NSLock()
    private var cache: [String: (name: String?, at: TimeInterval)] = [:]

    public init(runner: TmuxRunner) {
        self.runner = runner
    }

    public func name(forPane pane: String, now: TimeInterval) -> String? {
        lock.lock()
        let hit = cache[pane]
        lock.unlock()
        if let hit, now - hit.at >= 0, now - hit.at < Self.cacheTTL { return hit.name }
        let out = (try? runner.run(["display-message", "-p", "-t", pane, "#S"]))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let name = out?.isEmpty == false ? out : nil
        lock.lock()
        cache[pane] = (name, now)
        lock.unlock()
        return name
    }
}
