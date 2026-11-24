import Foundation

public struct EditorModel: Sendable {
    public static let undoLimit = 100

    private struct Snapshot: Sendable {
        var document: DeckConfig
        var pageIndex: Int
        var selection: String?
    }

    public private(set) var document: DeckConfig
    public private(set) var pageIndex: Int
    public private(set) var selection: String?
    private var saved: DeckConfig?
    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []
    private var lastCoalesce: String?

    public init(document: DeckConfig, saved: DeckConfig?) {
        self.document = Self.normalised(document)
        self.saved = saved
        self.pageIndex = 0
        self.selection = nil
    }

    private static func normalised(_ config: DeckConfig) -> DeckConfig {
        var c = config
        if c.pages.isEmpty { c.pages = [PageConfig(name: "Page 1", keys: [], live: [])] }
        return c
    }

    public var isDirty: Bool { saved == nil || document != saved }
    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }
    public var page: PageConfig { document.pages[pageIndex] }

    public func widgets(onPage index: Int) -> [EditorWidget] {
        guard document.pages.indices.contains(index) else { return [] }
        return EditorGrid.widgets(of: document.pages[index])
    }

    public func widget(_ id: String) -> EditorWidget? {
        widgets(onPage: pageIndex).first { $0.id == id }
    }

    public func canPlace(_ rect: CellRect, ignoring id: String?) -> Bool {
        EditorGrid.fits(rect, occupied: EditorGrid.occupied(widgets(onPage: pageIndex), ignoring: id))
    }

    public func canAdd(_ item: PaletteItem) -> Bool {
        let current = widgets(onPage: pageIndex)
        guard current.count < DeckConfig.maxWidgetsPerPage else { return false }
        return EditorGrid.firstFree(item.minSize, occupied: EditorGrid.occupied(current, ignoring: nil)) != nil
    }

    public func issues(_ env: IssueEnvironment) -> [EditorIssue] {
        EditorIssues.check(document, env)
    }

    public func hasErrors(_ env: IssueEnvironment) -> Bool {
        issues(env).contains { $0.severity == .error }
    }

    // MARK: Selection and pages

    public mutating func selectPage(_ index: Int) {
        lastCoalesce = nil
        pageIndex = min(max(index, 0), document.pages.count - 1)
        selection = nil
    }

    public mutating func select(_ id: String?) {
        lastCoalesce = nil
        if let id, widget(id) != nil { selection = id } else { selection = nil }
    }

    @discardableResult
    public mutating func addPage() -> Bool {
        guard document.pages.count < DeckConfig.maxPages else { return false }
        let names = Set(document.pages.map(\.name))
        var n = document.pages.count + 1
        while names.contains("Page \(n)") { n += 1 }
        let before = snapshot()
        document.pages.append(PageConfig(name: "Page \(n)", keys: [], live: []))
        pageIndex = document.pages.count - 1
        selection = nil
        record(before, coalesce: nil)
        return true
    }

    @discardableResult
    public mutating func removePage(at index: Int) -> Bool {
        guard document.pages.count > 1, document.pages.indices.contains(index) else { return false }
        let before = snapshot()
        document.pages.remove(at: index)
        if index < pageIndex {
            pageIndex -= 1
        } else if index == pageIndex {
            pageIndex = min(index, document.pages.count - 1)
        }
        selection = nil
        record(before, coalesce: nil)
        return true
    }

    @discardableResult
    public mutating func movePage(from: Int, to: Int) -> Bool {
        let count = document.pages.count
        guard from != to, (0..<count).contains(from), (0..<count).contains(to) else { return false }
        let before = snapshot()
        var order = Array(0..<count)
        order.insert(order.remove(at: from), at: to)
        document.pages.insert(document.pages.remove(at: from), at: to)
        pageIndex = order.firstIndex(of: pageIndex) ?? pageIndex
        record(before, coalesce: nil)
        return true
    }

    public mutating func renamePage(at index: Int, to name: String) {
        guard document.pages.indices.contains(index) else { return }
        let before = snapshot()
        document.pages[index].name = EditorText.prefix(name, maxBytes: DeckConfig.maxPageNameBytes)
        record(before, coalesce: "page-name-\(index)")
    }

    // MARK: Widgets

    @discardableResult
    public mutating func add(_ item: PaletteItem) -> String? {
        let current = widgets(onPage: pageIndex)
        let occupied = EditorGrid.occupied(current, ignoring: nil)
        guard current.count < DeckConfig.maxWidgetsPerPage,
              let rect = EditorGrid.firstFree(item.defaultSize, occupied: occupied)
                ?? EditorGrid.firstFree(item.minSize, occupied: occupied) else { return nil }
        return insert(item, at: rect)
    }

    @discardableResult
    public mutating func add(_ item: PaletteItem, col: Int, row: Int) -> String? {
        let current = widgets(onPage: pageIndex)
        guard current.count < DeckConfig.maxWidgetsPerPage else { return nil }
        let occupied = EditorGrid.occupied(current, ignoring: nil)
        let candidates = [CellRect(col: col, row: row, w: item.defaultSize.w, h: item.defaultSize.h).fitted(),
                          CellRect(col: col, row: row, w: item.minSize.w, h: item.minSize.h).fitted()]
        guard let rect = candidates.first(where: { EditorGrid.fits($0, occupied: occupied) }) else { return nil }
        return insert(item, at: rect)
    }

    private mutating func insert(_ item: PaletteItem, at rect: CellRect) -> String {
        let taken = Set(document.pages.flatMap { EditorGrid.widgets(of: $0).map(\.id) })
        let id = EditorIds.make(base: item.idBase, taken: taken)
        let before = snapshot()
        switch item.makeWidget(id: id, rect: rect) {
        case .key(let k): document.pages[pageIndex].keys.append(k)
        case .live(let l): document.pages[pageIndex].live.append(l)
        }
        selection = id
        record(before, coalesce: nil)
        return id
    }

    @discardableResult
    public mutating func setFrame(_ id: String, _ rect: CellRect) -> Bool {
        guard let current = widget(id) else { return false }
        let min = current.minSize
        guard rect.w >= min.w, rect.h >= min.h, canPlace(rect, ignoring: id) else { return false }
        guard rect != current.frame else { return true }
        let before = snapshot()
        mutate(id) { widget in
            switch widget {
            case .key(var k):
                (k.col, k.row, k.w, k.h) = (rect.col, rect.row, rect.w, rect.h)
                widget = .key(k)
            case .live(var l):
                (l.col, l.row, l.w, l.h) = (rect.col, rect.row, rect.w, rect.h)
                widget = .live(l)
            }
        }
        record(before, coalesce: nil)
        return true
    }

    @discardableResult
    public mutating func remove(_ id: String) -> Bool {
        guard widget(id) != nil else { return false }
        let before = snapshot()
        document.pages[pageIndex].keys.removeAll { $0.id == id }
        document.pages[pageIndex].live.removeAll { $0.id == id }
        if selection == id { selection = nil }
        record(before, coalesce: nil)
        return true
    }

    public mutating func updateKey(_ id: String, coalesce: String? = nil, _ change: (inout KeyConfig) -> Void) {
        guard let i = document.pages[pageIndex].keys.firstIndex(where: { $0.id == id }) else { return }
        let before = snapshot()
        let original = document.pages[pageIndex].keys[i]
        var edited = original
        change(&edited)
        (edited.id, edited.col, edited.row, edited.w, edited.h) =
            (original.id, original.col, original.row, original.w, original.h)
        document.pages[pageIndex].keys[i] = edited
        record(before, coalesce: coalesce)
    }

    @discardableResult
    public mutating func setStat(_ id: String, metric: StatMetric, style: StatStyle) -> Bool {
        guard let i = document.pages[pageIndex].live.firstIndex(where: { $0.id == id }),
              case .stat = document.pages[pageIndex].live[i].kind else { return false }
        let before = snapshot()
        document.pages[pageIndex].live[i].kind = .stat(metric, style)
        record(before, coalesce: nil)
        return true
    }

    public mutating func setAction(_ action: DeckAction?, slot: ActionSlot, for id: String,
                                   coalesce: String? = nil) {
        switch slot {
        case .primary:
            guard let action else { return }
            updateKey(id, coalesce: coalesce) { $0.action = action }
        case .long:
            updateKey(id, coalesce: coalesce) { $0.longAction = action }
        }
    }

    public mutating func chooseApp(_ app: AppEntry, slot: ActionSlot, for id: String) {
        updateKey(id) { key in
            let chosen = DeckAction.openApp(path: app.path)
            switch slot {
            case .long:
                key.longAction = chosen
            case .primary:
                var previousName: String?
                if case .openApp(let old) = key.action {
                    previousName = URL(fileURLWithPath: old).deletingPathExtension().lastPathComponent
                }
                key.action = chosen
                key.icon = .app(path: app.path)
                if key.label.isEmpty || key.label == "Key" || key.label == previousName {
                    key.label = app.name
                }
            }
        }
    }

    // MARK: History

    public mutating func undo() {
        lastCoalesce = nil
        guard let snap = undoStack.popLast() else { return }
        redoStack.append(snapshot())
        restore(snap)
    }

    public mutating func redo() {
        lastCoalesce = nil
        guard let snap = redoStack.popLast() else { return }
        undoStack.append(snapshot())
        restore(snap)
    }

    public mutating func load(_ config: DeckConfig) {
        document = Self.normalised(config)
        saved = config
        undoStack = []
        redoStack = []
        lastCoalesce = nil
        pageIndex = 0
        selection = nil
    }

    public mutating func markSaved() {
        saved = document
    }

    public mutating func externalChange(_ config: DeckConfig) {
        if config == document {
            saved = config
        } else if !isDirty {
            load(config)
        }
    }

    // MARK: Internals

    private func snapshot() -> Snapshot {
        Snapshot(document: document, pageIndex: pageIndex, selection: selection)
    }

    private mutating func restore(_ snap: Snapshot) {
        document = snap.document
        pageIndex = min(snap.pageIndex, document.pages.count - 1)
        selection = snap.selection.flatMap { widget($0) != nil ? $0 : nil }
    }

    private mutating func record(_ before: Snapshot, coalesce: String?) {
        guard document != before.document else { return }
        redoStack = []
        if coalesce == nil || coalesce != lastCoalesce {
            undoStack.append(before)
            if undoStack.count > Self.undoLimit { undoStack.removeFirst(undoStack.count - Self.undoLimit) }
        }
        lastCoalesce = coalesce
    }

    private mutating func mutate(_ id: String, _ body: (inout EditorWidget) -> Void) {
        if let i = document.pages[pageIndex].keys.firstIndex(where: { $0.id == id }) {
            var w = EditorWidget.key(document.pages[pageIndex].keys[i])
            body(&w)
            if case .key(let k) = w { document.pages[pageIndex].keys[i] = k }
        } else if let i = document.pages[pageIndex].live.firstIndex(where: { $0.id == id }) {
            var w = EditorWidget.live(document.pages[pageIndex].live[i])
            body(&w)
            if case .live(let l) = w { document.pages[pageIndex].live[i] = l }
        }
    }
}
