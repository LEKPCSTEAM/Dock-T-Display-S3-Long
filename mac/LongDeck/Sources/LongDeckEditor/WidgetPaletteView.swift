import LongDeckCore
import SwiftUI

public struct WidgetPaletteView: View {
    @ObservedObject var store: EditorStore

    public init(store: EditorStore) {
        self.store = store
    }

    public var body: some View {
        HStack(spacing: 8) {
            ForEach(PaletteItem.allCases, id: \.rawValue) { item in
                tile(item)
            }
        }
    }

    private func tile(_ item: PaletteItem) -> some View {
        VStack(spacing: 4) {
            Image(systemName: item.symbol).font(.system(size: 20))
            Text(item.title).font(.system(size: 11)).lineLimit(1)
        }
        .foregroundColor(BoardColors.text)
        .frame(width: 96, height: 64)
        .background(RoundedRectangle(cornerRadius: 8).fill(BoardColors.panelHi))
        .opacity(store.model.canAdd(item) ? 1 : 0.4)
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture { store.add(item) }
        .draggable(item.rawValue)
        .help("Drag onto the grid, or click to add at the first free spot")
    }
}
