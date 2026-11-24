public enum LayoutPushPolicy {
    public static let maxWebSocketFrame = 15 * 1024

    public static func fits(frameBytes: Int) -> Bool {
        frameBytes <= maxWebSocketFrame
    }
}
