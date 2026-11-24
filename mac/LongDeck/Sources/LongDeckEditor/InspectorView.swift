import AppKit
import LongDeckCore
import SwiftUI

public struct InspectorView: View {
    @ObservedObject var store: EditorStore

    public init(store: EditorStore) {
        self.store = store
    }

    private enum IconMode: Hashable { case none, app, symbol }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .padding(12)
            .frame(width: 320, alignment: .topLeading)
        }
        .frame(width: 320)
    }

    @ViewBuilder private var content: some View {
        if let id = store.model.selection, let widget = store.model.widget(id) {
            switch widget {
            case .key(let key): keySections(key)
            case .live(let live): liveSections(live)
            }
        } else {
            pageSection
        }
    }

    // MARK: Page

    private var pageSection: some View {
        let name = store.model.page.name
        let count = store.model.widgets(onPage: store.model.pageIndex).count
        let bytes = name.utf8.count
        return VStack(alignment: .leading, spacing: 8) {
            Text("Page").font(.headline)
            TextField("Page name", text: Binding(
                get: { store.model.page.name },
                set: { store.renamePage(at: store.model.pageIndex, to: $0) }))
                .textFieldStyle(.roundedBorder)
            Text("\(bytes)/23 bytes")
                .font(.caption)
                .foregroundColor(bytes > 23 ? BoardColors.err : .secondary)
            Text("\(count)/16 widgets")
                .font(.caption)
                .foregroundColor(.secondary)
            Divider()
            Text("Drag a widget from the palette onto the grid, or click it to add.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: Key

    @ViewBuilder private func keySections(_ key: KeyConfig) -> some View {
        header("Key", id: key.id)
        Divider()
        faceSection(key)
        Divider()
        sizeSection(key.id, CellRect(col: key.col, row: key.row, w: key.w, h: key.h), minSize: CellSize(w: 1, h: 1))
        Divider()
        VStack(alignment: .leading, spacing: 8) {
            Text("Action").font(.headline)
            ActionEditorView(store: store, keyId: key.id, slot: .primary)
        }
        Divider()
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Long press", isOn: Binding(
                get: { key.longAction != nil },
                set: { on in
                    store.setAction(on ? ActionKind.openApp.defaultAction : nil, slot: .long, for: key.id,
                                    coalesce: nil)
                }))
                .font(.headline)
            if key.longAction != nil {
                ActionEditorView(store: store, keyId: key.id, slot: .long)
            }
        }
        issuesSection(key.id)
    }

    private func header(_ title: String, id: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(.headline)
            Text(id).font(.system(.caption, design: .monospaced)).foregroundColor(.secondary)
            Spacer()
            Button { store.remove(id) } label: { Image(systemName: "trash") }
                .keyboardShortcut(.delete, modifiers: .command)
                .help("Remove (⌘⌫)")
        }
    }

    private func faceSection(_ key: KeyConfig) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Face").font(.headline)
            labeled("Label") {
                TextField("Label", text: Binding(
                    get: { key.label },
                    set: { value in store.updateKey(key.id, coalesce: "label-\(key.id)") { $0.label = value } }))
                    .textFieldStyle(.roundedBorder)
            }
            labeled("Icon") {
                Picker("Icon", selection: iconMode(key)) {
                    Text("None").tag(IconMode.none)
                    Text("App").tag(IconMode.app)
                    Text("Symbol").tag(IconMode.symbol)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            iconEditor(key)
            labeled("Background") {
                ColorPicker("Background", selection: Binding(
                    get: { color(key.background, fallback: .black) },
                    set: { value in
                        guard let hex = HexColor.from(NSColor(value)) else { return }
                        store.updateKey(key.id, coalesce: "background-\(key.id)") { $0.background = hex }
                    }), supportsOpacity: false)
                    .labelsHidden()
            }
            labeled("Text colour") {
                HStack {
                    ColorPicker("Text colour", selection: Binding(
                        get: { color(key.foreground, fallback: .white) },
                        set: { value in
                            guard let hex = HexColor.from(NSColor(value)) else { return }
                            store.updateKey(key.id, coalesce: "foreground-\(key.id)") { $0.foreground = hex }
                        }), supportsOpacity: false)
                        .labelsHidden()
                    Button("Default") { store.updateKey(key.id, coalesce: nil) { $0.foreground = nil } }
                        .disabled(key.foreground == nil)
                }
            }
            preview(key)
        }
    }

    private func color(_ hex: String?, fallback: Color) -> Color {
        guard let hex, let ns = HexColor.nsColor(hex) else { return fallback }
        return Color(nsColor: ns)
    }

    private func iconMode(_ key: KeyConfig) -> Binding<IconMode> {
        Binding(
            get: {
                switch key.icon {
                case nil: return .none
                case .app?: return .app
                case .symbol?: return .symbol
                }
            },
            set: { mode in
                let current: IconMode
                switch key.icon {
                case nil: current = .none
                case .app?: current = .app
                case .symbol?: current = .symbol
                }
                guard mode != current else { return }
                store.updateKey(key.id, coalesce: nil) {
                    switch mode {
                    case .none: $0.icon = nil
                    case .app: $0.icon = .app(path: "")
                    case .symbol: $0.icon = .symbol(name: "star.fill")
                    }
                }
            })
    }

    @ViewBuilder private func iconEditor(_ key: KeyConfig) -> some View {
        switch key.icon {
        case .app(let path)?:
            AppChooser(path: path) { app in
                store.updateKey(key.id, coalesce: nil) { $0.icon = .app(path: app.path) }
            }
        case .symbol(let name)?:
            HStack(spacing: 8) {
                TextField("Symbol name", text: Binding(
                    get: { name },
                    set: { value in
                        store.updateKey(key.id, coalesce: "symbol-\(key.id)") { $0.icon = .symbol(name: value) }
                    }))
                    .textFieldStyle(.roundedBorder)
                Menu {
                    ForEach(SymbolCatalog.common, id: \.self) { symbol in
                        Button {
                            store.updateKey(key.id, coalesce: nil) { $0.icon = .symbol(name: symbol) }
                        } label: {
                            Label(symbol, systemImage: symbol)
                        }
                    }
                } label: {
                    Image(systemName: "square.grid.3x3")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        case nil:
            EmptyView()
        }
    }

    private func preview(_ key: KeyConfig) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Group {
                if let image = FaceImageCache.shared.image(for: key) {
                    Image(decorative: image, scale: 1).interpolation(.none)
                } else {
                    Rectangle().fill(BoardColors.panel)
                        .frame(width: CGFloat(key.w * 80 - 6), height: CGFloat(key.h * 90 - 6))
                }
            }
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 8).fill(BoardColors.bg))
        }
    }

    // MARK: Live

    @ViewBuilder private func liveSections(_ live: LiveWidgetConfig) -> some View {
        header(LiveTitles.title(live.kind), id: live.id)
        Divider()
        if case .stat(let metric, let style) = live.kind {
            VStack(alignment: .leading, spacing: 8) {
                labeled("Metric") {
                    Picker("Metric", selection: Binding(
                        get: { metric },
                        set: { store.setStat(live.id, metric: $0, style: style) })) {
                        ForEach(StatMetric.allCases, id: \.self) { Text(LiveTitles.metricName($0)).tag($0) }
                    }
                    .labelsHidden()
                }
                labeled("Style") {
                    Picker("Style", selection: Binding(
                        get: { style },
                        set: { store.setStat(live.id, metric: metric, style: $0) })) {
                        ForEach(StatStyle.allCases, id: \.self) { Text(LiveTitles.styleName($0)).tag($0) }
                    }
                    .labelsHidden()
                }
            }
            Divider()
        }
        sizeSection(live.id, CellRect(col: live.col, row: live.row, w: live.w, h: live.h),
                    minSize: EditorWidget.live(live).minSize)
        Text("Drawn live on the board.").font(.caption).foregroundColor(.secondary)
        issuesSection(live.id)
    }

    // MARK: Shared

    private func sizeSection(_ id: String, _ rect: CellRect, minSize: CellSize) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Size").font(.headline)
            HStack {
                Stepper("W \(rect.w)", value: Binding(
                    get: { rect.w },
                    set: { store.setFrame(id, CellRect(col: rect.col, row: rect.row, w: $0, h: rect.h)) }),
                    in: minSize.w...DeckConfig.gridCols)
                Stepper("H \(rect.h)", value: Binding(
                    get: { rect.h },
                    set: { store.setFrame(id, CellRect(col: rect.col, row: rect.row, w: rect.w, h: $0)) }),
                    in: minSize.h...DeckConfig.gridRows)
            }
            Text("Size \(rect.w) x \(rect.h)  ·  Column \(rect.col), row \(rect.row)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder private func issuesSection(_ id: String) -> some View {
        let issues = store.issues(forWidget: id)
        if !issues.isEmpty {
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                Text("Issues").font(.headline)
                ForEach(Array(issues.enumerated()), id: \.offset) { _, issue in
                    Text(issue.message)
                        .font(.caption)
                        .foregroundColor(issue.severity == .error ? BoardColors.err : BoardColors.warn)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func labeled<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.caption).foregroundColor(.secondary).frame(width: 78, alignment: .leading)
            content()
        }
    }
}
