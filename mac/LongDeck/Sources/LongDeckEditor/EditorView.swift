import LongDeckCore
import SwiftUI

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

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button("Undo") { store.undo() }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!store.model.canUndo)
            Button("Redo") { store.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!store.model.canRedo)
            Text(store.model.page.name.isEmpty ? "Untitled" : store.model.page.name).font(.headline)
            Spacer()
            Text(store.status).foregroundColor(.secondary).lineLimit(1)
            Button("Save") { store.save() }
                .keyboardShortcut("s", modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(!store.canSave)
        }
    }
}
