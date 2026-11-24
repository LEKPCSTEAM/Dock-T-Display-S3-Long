import AppKit

@MainActor
final class AppIconCache {
    static let shared = AppIconCache()

    private let icons: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 512
        return cache
    }()

    func icon(path: String) -> NSImage {
        if let hit = icons.object(forKey: path as NSString) { return hit }
        let image = NSWorkspace.shared.icon(forFile: path)
        icons.setObject(image, forKey: path as NSString)
        return image
    }
}
