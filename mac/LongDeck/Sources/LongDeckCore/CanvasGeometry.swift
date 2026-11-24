import CoreGraphics

public enum ResizeHandle: CaseIterable, Sendable { case right, bottom, bottomRight }

public struct CanvasGeometry: Equatable, Sendable {
    public static let boardSize = CGSize(width: 640, height: 180)
    private static let cellWidth: CGFloat = 80
    private static let cellHeight: CGFloat = 90

    public var scale: CGFloat

    public init(scale: CGFloat) {
        self.scale = scale
    }

    public static func fitting(width: CGFloat) -> CanvasGeometry {
        CanvasGeometry(scale: min(2, max(1, (width / 640 * 4).rounded(.down) / 4)))
    }

    public var size: CGSize {
        CGSize(width: Self.boardSize.width * scale, height: Self.boardSize.height * scale)
    }

    public func rect(for cells: CellRect) -> CGRect {
        CGRect(x: CGFloat(cells.col) * Self.cellWidth + 3, y: CGFloat(cells.row) * Self.cellHeight + 3,
               width: CGFloat(cells.w) * Self.cellWidth - 6, height: CGFloat(cells.h) * Self.cellHeight - 6)
            .applying(CGAffineTransform(scaleX: scale, y: scale))
    }

    public func cell(at point: CGPoint) -> (col: Int, row: Int)? {
        guard point.x >= 0, point.y >= 0, point.x < size.width, point.y < size.height else { return nil }
        return (Int((point.x / (Self.cellWidth * scale)).rounded(.down)),
                Int((point.y / (Self.cellHeight * scale)).rounded(.down)))
    }

    public func moved(_ start: CellRect, by translation: CGSize) -> CellRect {
        var rect = start
        rect.col += cellDelta(translation.width, Self.cellWidth)
        rect.row += cellDelta(translation.height, Self.cellHeight)
        return rect.fitted()
    }

    public func resized(_ start: CellRect, handle: ResizeHandle, by translation: CGSize,
                        minSize: CellSize) -> CellRect {
        var rect = start
        if handle == .right || handle == .bottomRight {
            rect.col = min(start.col, DeckConfig.gridCols - minSize.w)
            let w = start.w + cellDelta(translation.width, Self.cellWidth)
            rect.w = clamp(w, minSize.w, DeckConfig.gridCols - rect.col)
        }
        if handle == .bottom || handle == .bottomRight {
            rect.row = min(start.row, DeckConfig.gridRows - minSize.h)
            let h = start.h + cellDelta(translation.height, Self.cellHeight)
            rect.h = clamp(h, minSize.h, DeckConfig.gridRows - rect.row)
        }
        return rect
    }

    private func cellDelta(_ distance: CGFloat, _ cell: CGFloat) -> Int {
        Int((distance / (cell * scale)).rounded(.toNearestOrAwayFromZero))
    }

    private func clamp(_ value: Int, _ low: Int, _ high: Int) -> Int {
        max(low, min(value, high))
    }
}
