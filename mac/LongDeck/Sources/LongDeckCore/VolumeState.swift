public struct VolumeState: Equatable, Sendable {
    public var level: Int
    public var muted: Bool
    public var available: Bool

    public init(level: Int, muted: Bool, available: Bool) {
        if available {
            self.level = max(0, min(100, level))
            self.muted = muted
            self.available = true
        } else {
            self.level = 0
            self.muted = false
            self.available = false
        }
    }

    public static let unavailable = VolumeState(level: 0, muted: false, available: false)

    public var jsonBody: String {
        "{\"available\":\(available),\"level\":\(level),\"muted\":\(muted)}"
    }
}

public enum VolumeError: Error, Equatable { case unavailable, status(Int32) }
