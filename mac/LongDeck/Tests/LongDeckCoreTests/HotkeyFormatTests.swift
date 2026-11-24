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
            #expect(HotkeyFormat.display(keyCode: code, modifiers: mods, translator: { _ in nil }) == text)
        }
    }

    @Test func printableKeysFollowTranslator() {
        let german: HotkeyFormat.Translator = { $0 == 6 ? "Y" : ($0 == 16 ? "Z" : nil) }
        #expect(HotkeyFormat.display(keyCode: 6, modifiers: [.command], translator: german) == "⌘Y")
        #expect(HotkeyFormat.keyName(16, translator: german) == "Z")
        #expect(HotkeyFormat.keyName(0, translator: german) == "A")
        #expect(HotkeyFormat.keyName(6, translator: { _ in "ย" }) == "ย")
        #expect(HotkeyFormat.keyName(123, translator: { _ in "x" }) == "←")
        #expect(HotkeyFormat.keyName(82, translator: { _ in "x" }) == "Num 0")
    }

    @Test func keypadHelpAndIsoNames() {
        let none: HotkeyFormat.Translator = { _ in nil }
        #expect(HotkeyFormat.keyName(82, translator: none) == "Num 0")
        #expect(HotkeyFormat.keyName(76, translator: none) == "Num ↩")
        #expect(HotkeyFormat.keyName(114, translator: none) == "Help")
        #expect(HotkeyFormat.keyName(10, translator: none) == "§")
        #expect(HotkeyFormat.keyName(77, translator: none) == "Key 77")
    }

    @Test func systemTranslatorIsSane() {
        let name = HotkeyFormat.keyName(0)
        #expect(!name.isEmpty)
        #expect(HotkeyFormat.keyName(36) == "↩")
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
