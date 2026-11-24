import AppKit
import SwiftUI

@MainActor
enum Snapshot {
    static func render<V: View>(_ view: V, size: CGSize) -> NSBitmapImageRep {
        _ = NSApplication.shared
        let host = NSHostingView(rootView: view)
        host.sizingOptions = []
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        let frameView = host.superview ?? host
        let rect = host.convert(host.bounds, to: frameView)
        let rep = frameView.bitmapImageRepForCachingDisplay(in: rect)!
        frameView.cacheDisplay(in: rect, to: rep)
        return rep
    }

    static func save(_ rep: NSBitmapImageRep, _ name: String) throws {
        guard let dir = ProcessInfo.processInfo.environment["LONGDECK_SNAPSHOT_DIR"] else { return }
        let url = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let png = rep.representation(using: .png, properties: [:])!
        try png.write(to: url.appendingPathComponent("\(name).png"))
    }

    static func isUniform(_ rep: NSBitmapImageRep) -> Bool {
        guard let data = rep.bitmapData else { return true }
        let bytes = rep.bytesPerRow * rep.pixelsHigh
        let bpp = max(rep.bitsPerPixel / 8, 1)
        guard bytes >= bpp else { return true }
        var i = bpp * 4
        while i + bpp <= bytes {
            for c in 0..<bpp where data[i + c] != data[c] { return false }
            i += bpp * 4
        }
        return true
    }
}
