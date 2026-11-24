import AppKit
import LongDeckCore
import LongDeckEditor
import SwiftUI

@MainActor
final class EditorWindowController: NSObject, NSWindowDelegate {
    private weak var model: AppModel?
    private var window: NSWindow?
    private var store: EditorStore?

    init(model: AppModel) {
        self.model = model
        super.init()
        AppDelegate.editor = self
    }

    func show() {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        guard let model else { return }
        let doc = model.editorDocument()
        let store = EditorStore(config: doc.config, onDisk: doc.onDisk, diskError: doc.diskError)
        store.onSave = { [weak model] in model?.saveFromEditor($0) ?? .failed("LongDeck is quitting") }
        model.onConfigApplied = { [weak store] in store?.externalChange($0) }
        model.onConfigInvalid = { [weak store] in store?.externalInvalid($0) }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = "LongDeck Editor"
        window.minSize = NSSize(width: 1200, height: 600)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: EditorView(store: store))
        window.delegate = self
        if !window.setFrameAutosaveName("LongDeckEditor") || !window.setFrameUsingName("LongDeckEditor") {
            window.center()
        }
        self.store = store
        self.window = window
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func closeForQuit() -> Bool {
        guard let window else { return true }
        guard confirmSaveIfNeeded() else { return false }
        window.close()
        return true
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        confirmSaveIfNeeded()
    }

    func windowWillClose(_ notification: Notification) {
        model?.onConfigApplied = nil
        model?.onConfigInvalid = nil
        store = nil
        window = nil
        NSApp.setActivationPolicy(.accessory)
    }

    private func confirmSaveIfNeeded() -> Bool {
        window?.makeFirstResponder(nil)
        guard let store, store.isDirty else { return true }
        let alert = NSAlert()
        alert.messageText = "Save changes to the layout?"
        alert.informativeText = store.closePromptDetail
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return store.save(overwriteConfirmed: true)
        case .alertSecondButtonReturn: return true
        default: return false
        }
    }
}
