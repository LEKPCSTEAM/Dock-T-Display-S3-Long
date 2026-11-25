import LongDeckCore
import SwiftUI

struct LivePlaceholderView: View {
    let kind: LiveKind
    let size: CellSize
    let scale: CGFloat

    init(kind: LiveKind, size: CellSize, scale: CGFloat) {
        self.kind = kind
        self.size = size
        self.scale = scale
    }

    private var width: CGFloat { CGFloat(size.w * 80 - 6) * scale }
    private var height: CGFloat { CGFloat(size.h * 90 - 6) * scale }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8 * scale).fill(BoardColors.panel)
            Text(LiveTitles.title(kind))
                .font(.system(size: 11 * scale))
                .foregroundColor(BoardColors.textDim)
                .lineLimit(1)
                .padding(.horizontal, 8 * scale)
                .padding(.top, 6 * scale)
            glyph
                .padding(.horizontal, 10 * scale)
                .padding(.top, 24 * scale)
                .padding(.bottom, 8 * scale)
        }
        .frame(width: width, height: height)
    }

    @ViewBuilder private var glyph: some View {
        switch kind {
        case .stat(_, .bar):
            bar(fraction: 0.6).frame(maxHeight: .infinity, alignment: .center)
        case .stat(_, .number):
            Text("42%")
                .font(.system(size: 28 * scale, weight: .semibold))
                .foregroundColor(BoardColors.text)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .stat(_, .sparkline):
            Sparkline().stroke(BoardColors.ok, lineWidth: 2 * scale)
        case .volume:
            HStack(spacing: 8 * scale) {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 16 * scale))
                    .foregroundColor(BoardColors.text)
                slider
            }
            .frame(maxHeight: .infinity)
        case .clock:
            Text("12:34")
                .font(.system(size: 28 * scale, weight: .semibold).monospacedDigit())
                .foregroundColor(BoardColors.text)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .claudeSessions:
            VStack(alignment: .leading, spacing: 6 * scale) {
                ForEach(0..<min(4, size.h * 2), id: \.self) { row in
                    HStack(spacing: 6 * scale) {
                        Circle().fill(row % 2 == 0 ? BoardColors.ok : BoardColors.warn)
                            .frame(width: 8 * scale, height: 8 * scale)
                        Capsule().fill(BoardColors.panelHi)
                            .frame(height: 8 * scale)
                    }
                }
                Spacer(minLength: 0)
            }
        case .claudeUsage:
            VStack(alignment: .leading, spacing: 4 * scale) {
                usageRow("5h", 0.6)
                usageRow("7d", 0.3)
            }
            .frame(maxHeight: .infinity)
        case .claudeAgents:
            Text("Claude agents")
                .font(.system(size: 14 * scale, weight: .semibold))
                .foregroundColor(BoardColors.text)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func bar(fraction: CGFloat) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(BoardColors.panelHi)
                Capsule().fill(BoardColors.ok).frame(width: proxy.size.width * fraction)
            }
        }
        .frame(height: 10 * scale)
    }

    private var slider: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(BoardColors.panelHi).frame(height: 6 * scale)
                Circle().fill(BoardColors.text)
                    .frame(width: 14 * scale, height: 14 * scale)
                    .offset(x: proxy.size.width * 0.4 - 7 * scale)
            }
            .frame(maxHeight: .infinity)
        }
    }

    private func usageRow(_ label: String, _ fraction: CGFloat) -> some View {
        HStack(spacing: 6 * scale) {
            Text(label)
                .font(.system(size: 10 * scale))
                .foregroundColor(BoardColors.text)
                .frame(width: 16 * scale, alignment: .leading)
            bar(fraction: fraction)
        }
    }
}

private struct Sparkline: Shape {
    private static let points: [CGFloat] = [0.2, 0.7, 0.3, 0.8, 0.4, 0.6, 0.2, 0.9, 0.5, 0.7, 0.3, 0.6]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let step = rect.width / CGFloat(Self.points.count - 1)
        for (i, value) in Self.points.enumerated() {
            let point = CGPoint(x: rect.minX + CGFloat(i) * step, y: rect.maxY - value * rect.height)
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}
