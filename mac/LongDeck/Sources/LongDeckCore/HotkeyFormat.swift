import AppKit

public enum HotkeyFormat {
    private static let keyNames: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B",
        12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4",
        22: "6", 23: "5", 25: "9", 26: "7", 28: "8", 29: "0", 31: "O", 32: "U", 34: "I", 35: "P",
        37: "L", 38: "J", 40: "K", 45: "N", 46: "M",
        24: "=", 27: "-", 30: "]", 33: "[", 39: "'", 41: ";", 42: "\\", 43: ",", 44: "/", 47: ".", 50: "`",
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

    public static func keyName(_ keyCode: UInt16) -> String {
        keyNames[keyCode] ?? "Key \(keyCode)"
    }

    public static func display(keyCode: UInt16, modifiers: [KeyModifier]) -> String {
        if keyCode == ActionKind.unsetKeyCode { return "Not set" }
        var glyphs = ""
        if modifiers.contains(.control) { glyphs += "⌃" }
        if modifiers.contains(.option) { glyphs += "⌥" }
        if modifiers.contains(.shift) { glyphs += "⇧" }
        if modifiers.contains(.command) { glyphs += "⌘" }
        return glyphs + keyName(keyCode)
    }

    public static func isCancel(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> Bool {
        keyCode == 53 && modifiers(from: flags).isEmpty
    }
}
