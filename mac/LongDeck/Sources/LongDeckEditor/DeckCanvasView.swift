import LongDeckCore
import SwiftUI

final class CanvasInteraction: ObservableObject {
    struct Ghost: Equatable {
        var id: String
        var rect: CellRect
        var valid: Bool
    }

    @Published var ghost: Ghost?
    @Published var dropTargeted = false
}

public struct DeckCanvasView: View {
    @ObservedObject var store: EditorStore
    @StateObject private var interaction: CanvasInteraction
    let geometry: CanvasGeometry

    public init(store: EditorStore, geometry: CanvasGeometry) {
        self.init(store: store, geometry: geometry, interaction: CanvasInteraction())
    }

    init(store: EditorStore, geometry: CanvasGeometry, interaction: CanvasInteraction) {
        self.store = store
        self.geometry = geometry
        _interaction = StateObject(wrappedValue: interaction)
    }

    private var scale: CGFloat { geometry.scale }
    private var widgets: [EditorWidget] { store.model.widgets(onPage: store.model.pageIndex) }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            BoardColors.bg
                .contentShape(Rectangle())
                .onTapGesture { store.select(nil) }
            gridLines
            ForEach(widgets, id: \.id) { widget in
                widgetView(widget)
            }
            ForEach(widgets, id: \.id) { widget in
                outlines(widget)
            }
            ghostView
            selectionHandles
            if interaction.dropTargeted {
                Rectangle().strokeBorder(Color.accentColor, lineWidth: 2)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        .dropDestination(for: String.self) { items, location in
            guard let raw = items.first, let item = PaletteItem(rawValue: raw),
                  let cell = geometry.cell(at: location) else { return false }
            return store.add(item, col: cell.col, row: cell.row) != nil
        } isTargeted: { interaction.dropTargeted = $0 }
    }

    private var gridLines: some View {
        ZStack(alignment: .topLeading) {
            ForEach(1..<8, id: \.self) { k in
                Rectangle().fill(BoardColors.panelHi)
                    .frame(width: 1, height: geometry.size.height)
                    .offset(x: CGFloat(k) * 80 * scale)
            }
            Rectangle().fill(BoardColors.panelHi)
                .frame(width: geometry.size.width, height: 1)
                .offset(y: 90 * scale)
        }
        .allowsHitTesting(false)
    }

    private func widgetView(_ widget: EditorWidget) -> some View {
        let rect = geometry.rect(for: widget.frame)
        let id = widget.id
        return content(widget, rect: rect)
            .frame(width: rect.width, height: rect.height)
            .opacity(interaction.ghost?.id == id ? 0.5 : 1)
            .contentShape(Rectangle())
            .onTapGesture { store.select(id) }
            .gesture(moveGesture(widget))
            .offset(x: rect.minX, y: rect.minY)
    }

    @ViewBuilder private func content(_ widget: EditorWidget, rect: CGRect) -> some View {
        switch widget {
        case .key(let key):
            if let image = FaceImageCache.shared.image(for: key) {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(scale.rounded() == scale ? .none : .medium)
                    .clipShape(RoundedRectangle(cornerRadius: 8 * scale))
            } else {
                Rectangle().fill(BoardColors.panel)
            }
        case .live(let live):
            LivePlaceholderView(kind: live.kind, size: CellSize(w: live.w, h: live.h), scale: scale)
        }
    }

    private func outlines(_ widget: EditorWidget) -> some View {
        let rect = geometry.rect(for: widget.frame)
        let issues = store.issues(forWidget: widget.id)
        let hasError = issues.contains { $0.severity == .error }
        let hasWarning = issues.contains { $0.severity == .warning }
        return ZStack(alignment: .topLeading) {
            if store.model.selection == widget.id {
                Rectangle().strokeBorder(Color.accentColor, lineWidth: 2)
                    .frame(width: rect.width, height: rect.height)
            }
            if hasError || hasWarning {
                Rectangle()
                    .strokeBorder(hasError ? BoardColors.err : BoardColors.warn,
                                  style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
                    .frame(width: rect.width - 4, height: rect.height - 4)
                    .offset(x: 2, y: 2)
            }
        }
        .frame(width: rect.width, height: rect.height, alignment: .topLeading)
        .offset(x: rect.minX, y: rect.minY)
        .allowsHitTesting(false)
    }

    @ViewBuilder private var ghostView: some View {
        if let ghost = interaction.ghost {
            let rect = geometry.rect(for: ghost.rect)
            let color = ghost.valid ? BoardColors.ok : BoardColors.err
            Rectangle().fill(color.opacity(0.15))
                .overlay(Rectangle().strokeBorder(color, lineWidth: 2))
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder private var selectionHandles: some View {
        if let id = store.model.selection, let widget = store.model.widget(id) {
            let rect = geometry.rect(for: widget.frame)
            ForEach(ResizeHandle.allCases, id: \.self) { handle in
                Rectangle().fill(Color.white)
                    .overlay(Rectangle().strokeBorder(Color.accentColor, lineWidth: 1.5))
                    .frame(width: 10, height: 10)
                    .contentShape(Rectangle())
                    .gesture(resizeGesture(widget, handle))
                    .offset(x: handlePoint(handle, rect).x - 5, y: handlePoint(handle, rect).y - 5)
            }
        }
    }

    private func handlePoint(_ handle: ResizeHandle, _ rect: CGRect) -> CGPoint {
        switch handle {
        case .right: return CGPoint(x: rect.maxX, y: rect.midY)
        case .bottom: return CGPoint(x: rect.midX, y: rect.maxY)
        case .bottomRight: return CGPoint(x: rect.maxX, y: rect.maxY)
        }
    }

    private func moveGesture(_ widget: EditorWidget) -> some Gesture {
        let id = widget.id
        let start = widget.frame
        return DragGesture(minimumDistance: 3)
            .onChanged { value in
                if store.model.selection != id { store.select(id) }
                updateGhost(id, geometry.moved(start, by: value.translation))
            }
            .onEnded { _ in finishDrag(id) }
    }

    private func resizeGesture(_ widget: EditorWidget, _ handle: ResizeHandle) -> some Gesture {
        let id = widget.id
        let start = widget.frame
        let minSize = widget.minSize
        return DragGesture(minimumDistance: 1)
            .onChanged { value in
                updateGhost(id, geometry.resized(start, handle: handle, by: value.translation, minSize: minSize))
            }
            .onEnded { _ in finishDrag(id) }
    }

    private func updateGhost(_ id: String, _ rect: CellRect) {
        let ghost = CanvasInteraction.Ghost(id: id, rect: rect, valid: store.model.canPlace(rect, ignoring: id))
        if interaction.ghost != ghost { interaction.ghost = ghost }
    }

    private func finishDrag(_ id: String) {
        if let ghost = interaction.ghost, ghost.id == id, ghost.valid { store.setFrame(id, ghost.rect) }
        interaction.ghost = nil
    }
}
