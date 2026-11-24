import SwiftUI

enum BoardColors {
    static let bg = hex(0x05070A)
    static let panel = hex(0x121820)
    static let panelHi = hex(0x1C2530)
    static let text = hex(0xF2F4F7)
    static let textDim = hex(0x7D8794)
    static let ok = hex(0x4ADE80)
    static let warn = hex(0xFBBF24)
    static let err = hex(0xF87171)

    private static func hex(_ value: UInt32) -> Color {
        Color(.sRGB, red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255,
              blue: Double(value & 0xFF) / 255, opacity: 1)
    }
}
