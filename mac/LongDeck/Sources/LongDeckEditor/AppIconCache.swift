import AppKit

@MainActor
final class AppIconCache {
    static let shared = AppIconCache()

    private var icons: [String: NSImage] = [:]

    func icon(path: String) -> NSImage {
        if let hit = icons[path] { return hit }
        let image = NSWorkspace.shared.icon(forFile: path)
        icons[path] = image
        return image
    }
}
