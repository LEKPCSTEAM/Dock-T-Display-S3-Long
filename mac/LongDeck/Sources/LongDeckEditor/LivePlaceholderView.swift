import LongDeckCore
import SwiftUI

struct LivePlaceholderView: View {
    let kind: LiveKind
    let size: CellSize
    let scale: CGFloat
    let sprites: AgentSprites?

    init(kind: LiveKind, size: CellSize, scale: CGFloat, sprites: AgentSprites? = nil) {
        self.kind = kind
        self.size = size
        self.scale = scale
        self.sprites = sprites
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
            if let sprites {
                HStack(spacing: 6 * scale) {
                    ForEach(0..<min(Self.sampleAgents.count, max(1, size.w / 2)), id: \.self) { index in
                        agentTile(sprites, Self.sampleAgents[index], state: index)
                    }
                }
            } else {
                Text("Claude agents")
                    .font(.system(size: 14 * scale, weight: .semibold))
                    .foregroundColor(BoardColors.text)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private static let sampleAgents = ["Agents Deck", "CMM iOS", "Heritage", "Wall Panel"]
    private static let stateColors = [BoardColors.ok, BoardColors.warn, BoardColors.textDim, BoardColors.panelHi]
    private static let hatTints = ["#4ADE80", "#60A5FA", "#F472B6", "#FBBF24", "#A78BFA", "#F87171", "#2DD4BF", "#F2F4F7"]
    private static let hatOpacity: UInt8 = 153

    private func agentTile(_ sprites: AgentSprites, _ name: String, state: Int) -> some View {
        VStack(spacing: 2 * scale) {
            if let image = Self.agentImage(sprites, name: name, state: state) {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
            }
            Text(name)
                .font(.system(size: 9 * scale))
                .foregroundColor(BoardColors.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(4 * scale)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 6 * scale).fill(BoardColors.panelHi))
        .overlay(alignment: .topTrailing) {
            Circle().fill(Self.stateColors[state % Self.stateColors.count])
                .frame(width: 6 * scale, height: 6 * scale)
                .padding(4 * scale)
        }
    }

    static func agentImage(_ sprites: AgentSprites, name: String, state: Int) -> CGImage? {
        guard state < sprites.tagRanges.count else { return nil }
        let frame = sprites.tagRanges[state].lowerBound
        guard frame < sprites.frames.count else { return nil }
        let (hat, tint) = AgentHat.of(name)
        guard hat < sprites.hats.count, let rgb = HexColor.parse(hatTints[tint]) else { return nil }
        let tint565 = rgb565(rgb)
        let (w, h) = (sprites.frameW, sprites.frameH)
        let src = [UInt8](sprites.frames[frame]), hatSrc = [UInt8](sprites.hats[hat])
        var out = [UInt8](repeating: 0, count: w * h * 3)
        for i in 0..<(w * h) where i * 3 + 2 < src.count {
            let base = FacePreview.mix(word(src, i), FacePreview.panel565, alpha: src[i * 3 + 2])
            put(&out, i, base)
        }
        for y in 0..<sprites.hatH {
            for x in 0..<sprites.hatW {
                let (px, py) = (sprites.hatX[frame] + x, sprites.hatY[frame] + y)
                let j = y * sprites.hatW + x
                guard px < w, py < h, j * 3 + 2 < hatSrc.count else { continue }
                let tinted = FacePreview.mix(tint565, word(hatSrc, j), alpha: hatOpacity)
                let i = py * w + px
                put(&out, i, FacePreview.mix(tinted, word(out, i), alpha: hatSrc[j * 3 + 2]))
            }
        }
        for i in 0..<(w * h) { out[i * 3 + 2] = 255 }
        return FacePreview.image(face: Data(out), width: w, height: h)
    }

    private static func word(_ bytes: [UInt8], _ i: Int) -> UInt16 {
        UInt16(bytes[i * 3]) << 8 | UInt16(bytes[i * 3 + 1])
    }

    private static func put(_ bytes: inout [UInt8], _ i: Int, _ v: UInt16) {
        bytes[i * 3] = UInt8(v >> 8)
        bytes[i * 3 + 1] = UInt8(v & 0xFF)
    }

    private static func rgb565(_ c: (r: UInt8, g: UInt8, b: UInt8)) -> UInt16 {
        UInt16(c.r >> 3) << 11 | UInt16(c.g >> 2) << 5 | UInt16(c.b >> 3)
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
