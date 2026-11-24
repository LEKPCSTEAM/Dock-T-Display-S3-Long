import AppKit

public enum HexColor {
    public static func parse(_ s: String) -> (r: UInt8, g: UInt8, b: UInt8)? {
        let digits = Array(s.utf8)
        guard digits.count == 7, digits[0] == UInt8(ascii: "#"),
              digits.dropFirst().allSatisfy({ $0.isASCIIHexDigit }),
              let v = UInt32(s.dropFirst(), radix: 16) else { return nil }
        return (UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF))
    }

    public static func format(r: UInt8, g: UInt8, b: UInt8) -> String {
        let hex = String(UInt32(r) << 16 | UInt32(g) << 8 | UInt32(b), radix: 16, uppercase: true)
        return "#" + String(repeating: "0", count: 6 - hex.count) + hex
    }

    public static func from(_ color: NSColor) -> String? {
        guard let c = color.usingColorSpace(.sRGB) else { return nil }
        func byte(_ v: CGFloat) -> UInt8 { UInt8(max(0, min(255, (v * 255).rounded()))) }
        return format(r: byte(c.redComponent), g: byte(c.greenComponent), b: byte(c.blueComponent))
    }

    public static func nsColor(_ s: String) -> NSColor? {
        guard let c = parse(s) else { return nil }
        return NSColor(srgbRed: CGFloat(c.r) / 255, green: CGFloat(c.g) / 255,
                       blue: CGFloat(c.b) / 255, alpha: 1)
    }
}

private extension UInt8 {
    var isASCIIHexDigit: Bool {
        (0x30...0x39).contains(self) || (0x41...0x46).contains(self) || (0x61...0x66).contains(self)
    }
}
