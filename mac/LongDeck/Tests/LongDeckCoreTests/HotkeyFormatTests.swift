import AppKit
import Testing
@testable import LongDeckCore

@Suite struct HotkeyFormatTests {
    @Test func modifiersCanonicalOrder() {
        let flags: NSEvent.ModifierFlags = [.shift, .command, .capsLock, .function]
        #expect(HotkeyFormat.modifiers(from: flags) == [.command, .shift])
    }

    @Test func displayVectors() {
        let vectors: [(UInt16, [KeyModifier], String)] = [
            (21, [.command, .shift], "⇧⌘4"),
            (49, [.command], "⌘Space"),
            (0, [.control, .option, .shift, .command], "⌃⌥⇧⌘A"),
            (122, [], "F1"),
            (123, [.option], "⌥←"),
            (200, [], "Key 200"),
            (65535, [], "Not set"),
        ]
        for (code, mods, text) in vectors {
            #expect(HotkeyFormat.display(keyCode: code, modifiers: mods) == text)
        }
    }

    @Test func actionFromEvent() {
        let action = HotkeyFormat.action(keyCode: 21, flags: [.command, .shift])
        #expect(action == .hotkey(keyCode: 21, modifiers: [.command, .shift]))
        let shot = SampleConfig.dev.pages.flatMap(\.keys).first { $0.id == "screenshot" }
        #expect(shot?.action == action)
    }

    @Test func cancelOnlyBareEscape() {
        #expect(HotkeyFormat.isCancel(keyCode: 53, flags: []))
        #expect(!HotkeyFormat.isCancel(keyCode: 53, flags: [.command]))
        #expect(!HotkeyFormat.isCancel(keyCode: 12, flags: []))
    }
}
