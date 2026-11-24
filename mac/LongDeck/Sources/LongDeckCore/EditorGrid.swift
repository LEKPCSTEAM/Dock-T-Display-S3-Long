public struct CellSize: Equatable, Hashable, Sendable {
    public var w: Int
    public var h: Int

    public init(w: Int, h: Int) {
        self.w = w
        self.h = h
    }
}

public struct CellRect: Equatable, Hashable, Sendable {
    public var col: Int
    public var row: Int
    public var w: Int
    public var h: Int

    public init(col: Int, row: Int, w: Int, h: Int) {
        self.col = col
        self.row = row
        self.w = w
        self.h = h
    }

    public var size: CellSize { CellSize(w: w, h: h) }

    public var isInGrid: Bool {
        w >= 1 && h >= 1 && col >= 0 && row >= 0
            && col + w <= DeckConfig.gridCols && row + h <= DeckConfig.gridRows
    }

    public var cells: Set<Int> {
        var result = Set<Int>()
        guard w >= 1, h >= 1 else { return result }
        for r in row..<(row + h) {
            for c in col..<(col + w) { result.insert(r * DeckConfig.gridCols + c) }
        }
        return result
    }

    public func intersects(_ other: CellRect) -> Bool {
        !cells.isDisjoint(with: other.cells)
    }

    public func fitted() -> CellRect {
        let fw = min(max(w, 1), DeckConfig.gridCols)
        let fh = min(max(h, 1), DeckConfig.gridRows)
        return CellRect(col: min(max(col, 0), DeckConfig.gridCols - fw),
                        row: min(max(row, 0), DeckConfig.gridRows - fh), w: fw, h: fh)
    }
}

public enum EditorWidget: Equatable, Sendable {
    case key(KeyConfig)
    case live(LiveWidgetConfig)

    public var id: String {
        switch self {
        case .key(let k): return k.id
        case .live(let l): return l.id
        }
    }

    public var frame: CellRect {
        switch self {
        case .key(let k): return CellRect(col: k.col, row: k.row, w: k.w, h: k.h)
        case .live(let l): return CellRect(col: l.col, row: l.row, w: l.w, h: l.h)
        }
    }

    public var minSize: CellSize {
        if case .live(let l) = self, l.kind == .claudeSessions { return CellSize(w: 2, h: 1) }
        return CellSize(w: 1, h: 1)
    }

    public var title: String {
        switch self {
        case .key(let k): return k.label.isEmpty ? "Key" : k.label
        case .live(let l): return LiveTitles.title(l.kind)
        }
    }
}

public enum EditorGrid {
    public static func widgets(of page: PageConfig) -> [EditorWidget] {
        page.keys.map(EditorWidget.key) + page.live.map(EditorWidget.live)
    }

    public static func occupied(_ widgets: [EditorWidget], ignoring id: String?) -> Set<Int> {
        var result = Set<Int>()
        for w in widgets where w.id != id { result.formUnion(w.frame.cells) }
        return result
    }

    public static func fits(_ rect: CellRect, occupied: Set<Int>) -> Bool {
        rect.isInGrid && rect.cells.isDisjoint(with: occupied)
    }

    public static func firstFree(_ size: CellSize, occupied: Set<Int>) -> CellRect? {
        for row in 0..<DeckConfig.gridRows {
            for col in 0..<DeckConfig.gridCols {
                let rect = CellRect(col: col, row: row, w: size.w, h: size.h)
                if fits(rect, occupied: occupied) { return rect }
            }
        }
        return nil
    }
}
