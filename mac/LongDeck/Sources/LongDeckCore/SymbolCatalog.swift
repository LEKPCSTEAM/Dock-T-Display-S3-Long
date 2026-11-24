import AppKit

public enum SymbolCatalog {
    public static let common: [String] = [
        "play.fill", "pause.fill", "playpause.fill", "forward.fill", "backward.fill",
        "speaker.wave.1.fill", "speaker.wave.3.fill", "speaker.slash.fill", "mic.fill", "mic.slash.fill",
        "camera.viewfinder", "magnifyingglass", "globe", "link", "terminal",
        "folder", "doc.text", "text.cursor", "keyboard", "bolt.fill",
        "star.fill", "heart.fill", "lock.fill", "moon.fill", "sun.max.fill",
        "gearshape.fill", "house.fill", "bell.fill", "hammer.fill", "cup.and.saucer.fill",
    ]

    public static func exists(_ name: String) -> Bool {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
    }
}
