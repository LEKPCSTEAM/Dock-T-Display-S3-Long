import AppKit
import CoreGraphics
import Foundation

public enum FaceRenderer {
    public static func faceSize(w: Int, h: Int) -> (Int, Int) {
        (w * 80 - 6, h * 90 - 6)
    }

    public static func pack(r: UInt8, g: UInt8, b: UInt8, a: UInt8) -> [UInt8] {
        let v = (UInt16(r >> 3) << 11) | (UInt16(g >> 2) << 5) | UInt16(b >> 3)
        return [UInt8(v >> 8), UInt8(v & 0xFF), a]
    }

    public static func render(_ key: KeyConfig) -> Data {
        let (width, height) = faceSize(w: key.w, h: key.h)
        var raw = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = raw.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(
                data: buf.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            draw(key, in: ctx, width: width, height: height)
            return true
        }
        guard drawn else { return Data(count: width * height * 3) }

        var out = Data(capacity: width * height * 3)
        for i in 0..<(width * height) {
            let a = raw[i * 4 + 3]
            var rgb = (raw[i * 4], raw[i * 4 + 1], raw[i * 4 + 2])
            if a > 0 && a < 255 {
                let unmul = { (c: UInt8) -> UInt8 in UInt8(min(255, Int(c) * 255 / Int(a))) }
                rgb = (unmul(rgb.0), unmul(rgb.1), unmul(rgb.2))
            }
            out.append(contentsOf: pack(r: rgb.0, g: rgb.1, b: rgb.2, a: a))
        }
        return out
    }

    private static func draw(_ key: KeyConfig, in ctx: CGContext, width: Int, height: Int) {
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        ctx.setFillColor(color(key.background))
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 10, cornerHeight: 10, transform: nil))
        ctx.fillPath()

        let gfx = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = gfx
        defer { NSGraphicsContext.restoreGraphicsState() }

        let foreground = key.foreground.flatMap(HexColor.nsColor)
        let labelBand: CGFloat = 22
        let iconArea = CGRect(x: 0, y: labelBand, width: CGFloat(width), height: CGFloat(height) * 0.6)
        if let image = icon(key.icon, tint: foreground ?? .white) {
            let side = min(iconArea.width, iconArea.height) - 8
            let target = CGRect(x: iconArea.midX - side / 2, y: iconArea.midY - side / 2,
                                width: side, height: side)
            image.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1)
        }

        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byTruncatingTail
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: foreground ?? NSColor.white,
            .paragraphStyle: style,
        ]
        let textRect = CGRect(x: 3, y: 3, width: CGFloat(width) - 6, height: labelBand - 3)
        (key.label as NSString).draw(with: textRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                                     attributes: attrs)
    }

    private static func icon(_ ref: IconRef?, tint: NSColor) -> NSImage? {
        switch ref {
        case .app(let path):
            guard FileManager.default.fileExists(atPath: path) else { return nil }
            return NSWorkspace.shared.icon(forFile: path)
        case .symbol(let name):
            guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
            let config = NSImage.SymbolConfiguration(pointSize: 36, weight: .regular)
            let sized = base.withSymbolConfiguration(config) ?? base
            return tinted(sized, tint)
        case nil:
            return nil
        }
    }

    private static func tinted(_ image: NSImage, _ color: NSColor) -> NSImage {
        let result = NSImage(size: image.size)
        result.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: image.size))
        color.set()
        NSRect(origin: .zero, size: image.size).fill(using: .sourceAtop)
        result.unlockFocus()
        return result
    }

    private static func color(_ hex: String) -> CGColor {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        let v = UInt32(s, radix: 16) ?? 0x333333
        return CGColor(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                       blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
}
