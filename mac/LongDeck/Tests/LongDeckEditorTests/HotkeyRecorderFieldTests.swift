import AppKit
import LongDeckCore
import Testing
@testable import LongDeckEditor

@Suite(.serialized) @MainActor struct HotkeyRecorderFieldTests {
    private final class Counter {
        var pushes = 0
        var pops = 0
    }

    private func installFakeMode() -> Counter {
        let counter = Counter()
        HotkeyRecorderField.symbolicHotKeys = SymbolicHotKeyMode(
            push: { counter.pushes += 1; return counter.pushes },
            pop: { _ in counter.pops += 1 })
        return counter
    }

    @Test func symbolicHotKeysPushedOncePerRecordingAndPopped() {
        let counter = installFakeMode()
        let (field, window, _) = makeField(fake: false)
        window.makeFirstResponder(field)
        #expect(counter.pushes == 1 && counter.pops == 0)
        window.makeFirstResponder(nil)
        #expect(counter.pushes == 1 && counter.pops == 1)
        window.makeFirstResponder(nil)
        #expect(counter.pops == 1)
        window.makeFirstResponder(field)
        field.removeFromSuperview()
        #expect(counter.pushes == 2 && counter.pops == 2)
    }

    @Test func symbolicHotKeysPoppedAfterRecordedShortcut() {
        let counter = installFakeMode()
        let (field, window, _) = makeField(fake: false)
        window.makeFirstResponder(field)
        field.handle(keyDown(21, flags: [.command, .shift], window: window))
        #expect(counter.pushes == 1 && counter.pops == 1)
    }

    private func makeField(fake: Bool = true) -> (HotkeyRecorderField, NSWindow, [DeckAction]) {
        if fake { _ = installFakeMode() }
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 100),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let container = NSView(frame: window.contentView!.bounds)
        window.contentView = container
        let field = HotkeyRecorderField(keyCode: 36, modifiers: [])
        container.addSubview(field)
        return (field, window, [])
    }

    private func keyDown(_ code: UInt16, flags: NSEvent.ModifierFlags = [], isRepeat: Bool = false,
                         window: NSWindow) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                         windowNumber: window.windowNumber, context: nil, characters: "x",
                         charactersIgnoringModifiers: "x", isARepeat: isRepeat, keyCode: code)!
    }

    @Test func recordsShortcutAndStops() {
        let (field, window, _) = makeField()
        var recorded: [DeckAction] = []
        field.onRecord = { recorded.append($0) }
        window.makeFirstResponder(field)
        #expect(field.isRecording)
        let result = field.handle(keyDown(21, flags: [.command, .shift], window: window))
        #expect(result == nil)
        #expect(recorded == [.hotkey(keyCode: 21, modifiers: [.command, .shift])])
        #expect(field.keyCode == 21)
        #expect(!field.isRecording)
        #expect(!field.hasMonitor)
    }

    @Test func escapeCancels() {
        let (field, window, _) = makeField()
        var recorded: [DeckAction] = []
        field.onRecord = { recorded.append($0) }
        window.makeFirstResponder(field)
        #expect(field.handle(keyDown(53, window: window)) == nil)
        #expect(recorded.isEmpty)
        #expect(!field.isRecording)
        #expect(field.keyCode == 36)
    }

    @Test func idleFieldPassesEventsThrough() {
        let (field, window, _) = makeField()
        let event = keyDown(21, window: window)
        #expect(field.handle(event) === event)
    }

    @Test func foreignWindowEventPassesThrough() {
        let (field, window, _) = makeField()
        var recorded: [DeckAction] = []
        field.onRecord = { recorded.append($0) }
        window.makeFirstResponder(field)
        let foreign = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command], timestamp: 0,
                                       windowNumber: 0, context: nil, characters: "q",
                                       charactersIgnoringModifiers: "q", isARepeat: false, keyCode: 12)!
        #expect(field.handle(foreign) === foreign)
        #expect(recorded.isEmpty)
        #expect(field.isRecording)
        window.makeFirstResponder(nil)
    }

    @Test func repeatIgnored() {
        let (field, window, _) = makeField()
        var recorded: [DeckAction] = []
        field.onRecord = { recorded.append($0) }
        window.makeFirstResponder(field)
        #expect(field.handle(keyDown(21, isRepeat: true, window: window)) == nil)
        #expect(recorded.isEmpty)
        #expect(field.isRecording)
        window.makeFirstResponder(nil)
    }

    @Test func monitorRemovedWhenLeavingWindow() {
        let (field, window, _) = makeField()
        window.makeFirstResponder(field)
        #expect(field.hasMonitor)
        field.removeFromSuperview()
        #expect(!field.hasMonitor)
        #expect(!field.isRecording)
    }

    @Test func oneMonitorOnly() {
        let (field, window, _) = makeField()
        let baseline = HotkeyRecorderField.installedMonitors
        window.makeFirstResponder(field)
        #expect(HotkeyRecorderField.installedMonitors == baseline + 1)
        window.makeFirstResponder(nil)
        #expect(HotkeyRecorderField.installedMonitors == baseline)
        window.makeFirstResponder(field)
        #expect(HotkeyRecorderField.installedMonitors == baseline + 1)
        window.makeFirstResponder(nil)
        #expect(HotkeyRecorderField.installedMonitors == baseline)
    }
}
