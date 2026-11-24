import AppKit
import LongDeckCore
import SwiftUI

enum SaveCommit {
    static func run(resign: () -> Void, schedule: (@escaping () -> Void) -> Void,
                    save: @escaping () -> Void) {
        resign()
        schedule(save)
    }
}

enum UndoRouting {
    static func storeHandlesUndo(firstResponder: NSResponder?) -> Bool {
        !(firstResponder is NSText)
    }
}

public struct EditorView: View {
    @ObservedObject var store: EditorStore

    public init(store: EditorStore) {
        self.store = store
    }

    public var body: some View {
        VStack(spacing: 0) {
            if let diskError = store.diskError {
                Text(diskError)
                    .foregroundColor(.black)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(BoardColors.warn)
            }
            HStack(spacing: 0) {
                PageListView(store: store)
                Divider()
                centre
                Divider()
                InspectorView(store: store)
            }
        }
        .frame(minWidth: 1200, minHeight: 600)
    }

    private var centre: some View {
        GeometryReader { proxy in
            let geometry = CanvasGeometry.fitting(width: proxy.size.width - 32)
            VStack(alignment: .leading, spacing: 12) {
                toolbar
                DeckCanvasView(store: store, geometry: geometry)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                WidgetPaletteView(store: store)
                IssueListView(store: store)
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
    }

    private func performUndo(redo: Bool) {
        if UndoRouting.storeHandlesUndo(firstResponder: NSApp.keyWindow?.firstResponder) {
            if redo { store.redo() } else { store.undo() }
        } else {
            NSApp.sendAction(Selector(redo ? "redo:" : "undo:"), to: nil, from: nil)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button("Undo") { performUndo(redo: false) }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!store.model.canUndo)
            Button("Redo") { performUndo(redo: true) }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!store.model.canRedo)
            Text(store.model.page.name.isEmpty ? "Untitled" : store.model.page.name).font(.headline)
            Spacer()
            Text(store.status).foregroundColor(.secondary).lineLimit(1)
            Button("Save") {
                SaveCommit.run(resign: { NSApp.keyWindow?.makeFirstResponder(nil) },
                               schedule: { DispatchQueue.main.async(execute: $0) },
                               save: { store.save() })
            }
                .keyboardShortcut("s", modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(!store.canSave)
        }
    }
}
