import CoreGraphics
import LongDeckCore

@MainActor
final class FaceImageCache {
    static let shared = FaceImageCache()
    private static let capacity = 256

    private var images: [String: CGImage] = [:]
    private var order: [String] = []

    func image(for key: KeyConfig) -> CGImage? {
        let cacheKey = FacePreview.cacheKey(key)
        if let hit = images[cacheKey] { return hit }
        guard let made = FacePreview.image(for: key) else { return nil }
        if order.count >= Self.capacity {
            images.removeValue(forKey: order.removeFirst())
        }
        images[cacheKey] = made
        order.append(cacheKey)
        return made
    }
}
