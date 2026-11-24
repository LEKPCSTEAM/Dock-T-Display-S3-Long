import AppKit
import LongDeckCore
import SwiftUI

final class HotkeyRecorderField: NSView {
    nonisolated(unsafe) static var installedMonitors = 0

    var keyCode: UInt16 {
        didSet { needsDisplay = true }
    }
    var modifiers: [KeyModifier] {
        didSet { needsDisplay = true }
    }
    var onRecord: ((DeckAction) -> Void)?
    private(set) var isRecording = false
    private var monitor: Any?
    private var heldFlags: NSEvent.ModifierFlags = []

    var hasMonitor: Bool { monitor != nil }

    init(keyCode: UInt16, modifiers: [KeyModifier]) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        super.init(frame: NSRect(x: 0, y: 0, width: 180, height: 24))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 180, height: 24) }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func becomeFirstResponder() -> Bool {
        guard super.becomeFirstResponder() else { return false }
        if monitor == nil {
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
                self?.handle(event) ?? event
            }
            Self.installedMonitors += 1
        }
        heldFlags = []
        isRecording = true
        needsDisplay = true
        return true
    }

    override func resignFirstResponder() -> Bool {
        guard super.resignFirstResponder() else { return false }
        stopRecording()
        return true
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { stopRecording() }
        super.viewWillMove(toWindow: newWindow)
    }

    deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            Self.installedMonitors -= 1
        }
    }

    @discardableResult
    func handle(_ event: NSEvent) -> NSEvent? {
        guard isRecording, event.window === window else { return event }
        if event.type == .flagsChanged {
            heldFlags = event.modifierFlags
            needsDisplay = true
            return event
        }
        guard event.type == .keyDown else { return event }
        if event.isARepeat { return nil }
        if HotkeyFormat.isCancel(keyCode: event.keyCode, flags: event.modifierFlags) {
            endRecording()
            return nil
        }
        let action = HotkeyFormat.action(keyCode: event.keyCode, flags: event.modifierFlags)
        keyCode = event.keyCode
        modifiers = HotkeyFormat.modifiers(from: event.modifierFlags)
        onRecord?(action)
        endRecording()
        return nil
    }

    private func endRecording() {
        if let window { window.makeFirstResponder(nil) }
        stopRecording()
    }

    private func stopRecording() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
            Self.installedMonitors -= 1
        }
        isRecording = false
        needsDisplay = true
    }

    private var heldGlyphs: String {
        var glyphs = ""
        if heldFlags.contains(.control) { glyphs += "⌃" }
        if heldFlags.contains(.option) { glyphs += "⌥" }
        if heldFlags.contains(.shift) { glyphs += "⇧" }
        if heldFlags.contains(.command) { glyphs += "⌘" }
        return glyphs
    }

    private var caption: String {
        guard isRecording else { return HotkeyFormat.display(keyCode: keyCode, modifiers: modifiers) }
        let glyphs = heldGlyphs
        return glyphs.isEmpty ? "Type a shortcut (esc cancels)" : glyphs + "…"
    }

    override func draw(_ dirtyRect: NSRect) {
        let border = isRecording ? NSColor.controlAccentColor : NSColor.separatorColor
        let width: CGFloat = isRecording ? 2 : 1
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: width / 2, dy: width / 2), xRadius: 5, yRadius: 5)
        NSColor.controlBackgroundColor.setFill()
        path.fill()
        border.setStroke()
        path.lineWidth = width
        path.stroke()
        let dim = isRecording && heldGlyphs.isEmpty
            || (!isRecording && keyCode == ActionKind.unsetKeyCode)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: dim ? NSColor.secondaryLabelColor : NSColor.labelColor,
        ]
        let text = NSAttributedString(string: caption, attributes: attributes)
        let size = text.size()
        text.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2))
    }
}

struct HotkeyRecorderView: NSViewRepresentable {
    let keyCode: UInt16
    let modifiers: [KeyModifier]
    let onRecord: (DeckAction) -> Void

    init(keyCode: UInt16, modifiers: [KeyModifier], onRecord: @escaping (DeckAction) -> Void) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.onRecord = onRecord
    }

    func makeNSView(context: Context) -> HotkeyRecorderField {
        let field = HotkeyRecorderField(keyCode: keyCode, modifiers: modifiers)
        field.onRecord = onRecord
        return field
    }

    func updateNSView(_ field: HotkeyRecorderField, context: Context) {
        field.onRecord = onRecord
        if field.keyCode != keyCode { field.keyCode = keyCode }
        if field.modifiers != modifiers { field.modifiers = modifiers }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: HotkeyRecorderField, context: Context) -> CGSize? {
        CGSize(width: 180, height: 24)
    }
}
