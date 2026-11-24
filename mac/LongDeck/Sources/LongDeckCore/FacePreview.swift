import CoreGraphics
import Foundation

public enum FacePreview {
    public static let panel565: UInt16 = 0x10C4

    public static func expand(_ rgb565: UInt16) -> (r: UInt8, g: UInt8, b: UInt8) {
        let r5 = UInt8(rgb565 >> 11), g6 = UInt8((rgb565 >> 5) & 0x3F), b5 = UInt8(rgb565 & 0x1F)
        return (r5 << 3 | r5 >> 2, g6 << 2 | g6 >> 4, b5 << 3 | b5 >> 2)
    }

    public static func mix(_ fg: UInt16, _ bg: UInt16, alpha: UInt8) -> UInt16 {
        if alpha < 3 { return bg }
        if alpha > 252 { return fg }
        let a = UInt32(alpha)
        func channel(_ f: UInt16, _ b: UInt16, shift: UInt16, mask: UInt16) -> UInt32 {
            let fc = UInt32((f >> shift) & mask), bc = UInt32((b >> shift) & mask)
            return ((fc * a + bc * (255 - a) + 128) * 0x8081) >> 23
        }
        let r = channel(fg, bg, shift: 11, mask: 0x1F)
        let g = channel(fg, bg, shift: 5, mask: 0x3F)
        let b = channel(fg, bg, shift: 0, mask: 0x1F)
        return UInt16(r << 11 | g << 5 | b)
    }

    public static func composite(face: Data, width: Int, height: Int) -> [UInt8] {
        var out = [UInt8](repeating: 255, count: width * height * 4)
        let bytes = [UInt8](face)
        for i in 0..<(width * height) where i * 3 + 2 < bytes.count {
            let v = UInt16(bytes[i * 3]) << 8 | UInt16(bytes[i * 3 + 1])
            let (r, g, b) = expand(mix(v, panel565, alpha: bytes[i * 3 + 2]))
            out[i * 4] = r
            out[i * 4 + 1] = g
            out[i * 4 + 2] = b
        }
        return out
    }

    public static func image(face: Data, width: Int, height: Int) -> CGImage? {
        let pixels = composite(face: face, width: width, height: height)
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: space,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    public static func image(for key: KeyConfig) -> CGImage? {
        let (w, h) = FaceRenderer.faceSize(w: key.w, h: key.h)
        return image(face: FaceRenderer.render(key), width: w, height: h)
    }

    public static func cacheKey(_ key: KeyConfig) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let part = CacheKey(w: key.w, h: key.h, label: key.label, icon: key.icon,
                            background: key.background, foreground: key.foreground)
        return (try? String(decoding: encoder.encode(part), as: UTF8.self)) ?? ""
    }

    private struct CacheKey: Codable, Sendable {
        var w: Int
        var h: Int
        var label: String
        var icon: IconRef?
        var background: String
        var foreground: String?
    }
}
