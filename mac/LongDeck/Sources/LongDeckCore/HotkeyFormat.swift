import AppKit
import Carbon.HIToolbox

public enum HotkeyFormat {
    public typealias Translator = @Sendable (UInt16) -> String?

    private static let printableNames: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 10: "§", 11: "B",
        12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4",
        22: "6", 23: "5", 25: "9", 26: "7", 28: "8", 29: "0", 31: "O", 32: "U", 34: "I", 35: "P",
        37: "L", 38: "J", 40: "K", 45: "N", 46: "M",
        24: "=", 27: "-", 30: "]", 33: "[", 39: "'", 41: ";", 42: "\\", 43: ",", 44: "/", 47: ".", 50: "`",
    ]

    private static let fixedNames: [UInt16: String] = [
        65: "Num .", 67: "Num *", 69: "Num +", 71: "Num ⌧", 75: "Num /", 76: "Num ↩", 78: "Num -",
        81: "Num =", 82: "Num 0", 83: "Num 1", 84: "Num 2", 85: "Num 3", 86: "Num 4", 87: "Num 5",
        88: "Num 6", 89: "Num 7", 91: "Num 8", 92: "Num 9", 114: "Help",
        36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋", 115: "↖", 116: "⇞", 117: "⌦", 119: "↘",
        121: "⇟", 123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15",
        106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20",
    ]

    public static func modifiers(from flags: NSEvent.ModifierFlags) -> [KeyModifier] {
        var result: [KeyModifier] = []
        if flags.contains(.command) { result.append(.command) }
        if flags.contains(.shift) { result.append(.shift) }
        if flags.contains(.option) { result.append(.option) }
        if flags.contains(.control) { result.append(.control) }
        return result
    }

    public static func action(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> DeckAction {
        .hotkey(keyCode: keyCode, modifiers: modifiers(from: flags))
    }

    public static func keyName(_ keyCode: UInt16, translator: Translator = layoutTranslator) -> String {
        if let fixed = fixedNames[keyCode] { return fixed }
        if let us = printableNames[keyCode] {
            if let typed = translator(keyCode), !typed.isEmpty { return typed }
            return us
        }
        return "Key \(keyCode)"
    }

    public static let layoutTranslator: Translator = { keyCode in
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue()
        guard let bytes = CFDataGetBytePtr(data) else { return nil }
        let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
        var deadKeys: UInt32 = 0
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        let status = UCKeyTranslate(layout, keyCode, UInt16(kUCKeyActionDisplay), 0,
                                    UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                    &deadKeys, chars.count, &length, &chars)
        guard status == noErr, length > 0 else { return nil }
        let text = String(utf16CodeUnits: chars, count: length).uppercased()
        return text.unicodeScalars.allSatisfy { $0.value > 0x20 && $0.value != 0x7F } ? text : nil
    }

    public static func display(keyCode: UInt16, modifiers: [KeyModifier],
                               translator: Translator = layoutTranslator) -> String {
        if keyCode == ActionKind.unsetKeyCode { return "Not set" }
        var glyphs = ""
        if modifiers.contains(.control) { glyphs += "⌃" }
        if modifiers.contains(.option) { glyphs += "⌥" }
        if modifiers.contains(.shift) { glyphs += "⇧" }
        if modifiers.contains(.command) { glyphs += "⌘" }
        return glyphs + keyName(keyCode, translator: translator)
    }

    public static func isCancel(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> Bool {
        keyCode == 53 && modifiers(from: flags).isEmpty
    }
}
