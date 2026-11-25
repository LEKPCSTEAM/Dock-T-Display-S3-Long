import CoreGraphics
import Foundation
import ImageIO

public enum AgentSpritesError: Error, Equatable, CustomStringConvertible {
    case invalid(String)

    public var description: String {
        switch self {
        case .invalid(let message): return message
        }
    }
}

public struct AgentSprites: Sendable, Equatable {
    public static let tagNames = ["working", "permission", "waiting", "done"]
    public static let scale = 3
    public static let hatCount = 8
    static let maxFrameNative = (w: 24, h: 24)
    static let maxHatNative = (w: 24, h: 12)
    static let maxTagFrames = 8
    static let maxFaces = 64

    public var frameW: Int, frameH: Int, hatW: Int, hatH: Int
    public var frames: [Data]
    public var tagRanges: [Range<Int>]
    public var durationsMs: [Int]
    public var hatX: [Int], hatY: [Int]
    public var hats: [Data]

    public static func load(agentJSON: Data, agentPNG: Data, hatsJSON: Data, hatsPNG: Data) throws -> AgentSprites {
        let agent = try Sheet(json: agentJSON, png: agentPNG)
        let hatSheet = try Sheet(json: hatsJSON, png: hatsPNG)

        let (fw, fh) = try agent.uniformSize(what: "agent frame")
        guard fw <= maxFrameNative.w, fh <= maxFrameNative.h else {
            throw AgentSpritesError.invalid("agent frame \(fw)x\(fh) is over \(maxFrameNative.w)x\(maxFrameNative.h)")
        }
        guard hatSheet.rects.count == hatCount else {
            throw AgentSpritesError.invalid("hats sheet has \(hatSheet.rects.count) frames, needs \(hatCount)")
        }
        let (hw, hh) = try hatSheet.uniformSize(what: "hat frame")
        guard hw <= maxHatNative.w, hh <= maxHatNative.h else {
            throw AgentSpritesError.invalid("hat frame \(hw)x\(hh) is over \(maxHatNative.w)x\(maxHatNative.h)")
        }

        var order: [Int] = []
        var ranges: [Range<Int>] = []
        for name in tagNames {
            guard let tag = agent.tags.first(where: { $0.name == name }) else {
                throw AgentSpritesError.invalid("missing tag \(name)")
            }
            let count = tag.to - tag.from + 1
            guard tag.from >= 0, tag.to < agent.rects.count, (1...maxTagFrames).contains(count) else {
                throw AgentSpritesError.invalid("tag \(name) must cover 1...\(maxTagFrames) existing frames")
            }
            ranges.append(order.count..<(order.count + count))
            order += Array(tag.from...tag.to)
        }
        guard order.count + hatCount <= maxFaces else {
            throw AgentSpritesError.invalid("\(order.count) frames and \(hatCount) hats are over \(maxFaces) faces")
        }

        let keys = agent.hatKeys
        guard !keys.isEmpty else { throw AgentSpritesError.invalid("missing hat slice") }
        var hx: [Int] = [], hy: [Int] = []
        for index in order {
            guard let key = keys.last(where: { $0.frame <= index }) else {
                throw AgentSpritesError.invalid("hat slice has no key for frame \(index)")
            }
            let x = key.x * scale, y = key.y * scale
            guard (0...255).contains(x), (0...255).contains(y) else {
                throw AgentSpritesError.invalid("hat position \(key.x),\(key.y) does not fit")
            }
            hx.append(x)
            hy.append(y)
        }

        let durations = order.map { agent.durations[$0] }
        guard durations.allSatisfy({ (0...65535).contains($0) }) else {
            throw AgentSpritesError.invalid("frame duration out of range")
        }

        return AgentSprites(
            frameW: fw * scale, frameH: fh * scale, hatW: hw * scale, hatH: hh * scale,
            frames: order.map { agent.face($0) }, tagRanges: ranges, durationsMs: durations,
            hatX: hx, hatY: hy, hats: (0..<hatCount).map { hatSheet.face($0) })
    }

    public static func loadFiles(in dir: URL) -> AgentSprites? {
        func read(_ name: String) -> Data? { try? Data(contentsOf: dir.appendingPathComponent(name)) }
        guard let agentJSON = read("claude-agent.json"), let agentPNG = read("claude-agent.png"),
              let hatsJSON = read("claude-hats.json"), let hatsPNG = read("claude-hats.png") else { return nil }
        return try? load(agentJSON: agentJSON, agentPNG: agentPNG, hatsJSON: hatsJSON, hatsPNG: hatsPNG)
    }

    public static func bundled() -> AgentSprites? { bundledSprites }

    private static let bundledSprites: AgentSprites? = {
        guard let dir = spritesDirectory() else { return nil }
        return loadFiles(in: dir)
    }()

    private static func spritesDirectory() -> URL? {
        let name = "LongDeck_LongDeckCore.bundle"
        let anchor = Bundle(for: BundleAnchor.self).bundleURL
        let parents = [Bundle.main.resourceURL, Bundle.main.bundleURL, anchor.deletingLastPathComponent()]
        for parent in parents.compactMap({ $0 }) {
            let candidate = parent.appendingPathComponent(name)
            if let bundle = Bundle(url: candidate), let dir = bundle.url(forResource: "sprites", withExtension: nil) {
                return dir
            }
        }
        return nil
    }
}

private final class BundleAnchor {}

private struct Sheet {
    struct Tag { var name: String; var from: Int; var to: Int }
    struct HatKey { var frame: Int; var x: Int; var y: Int }

    var rects: [CGRect] = []
    var durations: [Int] = []
    var tags: [Tag] = []
    var hatKeys: [HatKey] = []
    private var width = 0
    private var height = 0
    private var raw: [UInt8] = []

    init(json: Data, png: Data) throws {
        guard let root = try JSONSerialization.jsonObject(with: json) as? [String: Any],
              let frames = root["frames"] as? [[String: Any]] else {
            throw AgentSpritesError.invalid("sheet json has no frames array")
        }
        for f in frames {
            guard let r = f["frame"] as? [String: Any], let x = r["x"] as? Int, let y = r["y"] as? Int,
                  let w = r["w"] as? Int, let h = r["h"] as? Int, let d = f["duration"] as? Int else {
                throw AgentSpritesError.invalid("frame entry is malformed")
            }
            rects.append(CGRect(x: x, y: y, width: w, height: h))
            durations.append(d)
        }
        let meta = root["meta"] as? [String: Any] ?? [:]
        for t in meta["frameTags"] as? [[String: Any]] ?? [] {
            guard let name = t["name"] as? String, let from = t["from"] as? Int, let to = t["to"] as? Int else {
                throw AgentSpritesError.invalid("frame tag is malformed")
            }
            tags.append(Tag(name: name, from: from, to: to))
        }
        for s in meta["slices"] as? [[String: Any]] ?? [] where s["name"] as? String == "hat" {
            for k in s["keys"] as? [[String: Any]] ?? [] {
                guard let frame = k["frame"] as? Int, let b = k["bounds"] as? [String: Any],
                      let x = b["x"] as? Int, let y = b["y"] as? Int else {
                    throw AgentSpritesError.invalid("hat slice key is malformed")
                }
                hatKeys.append(HatKey(frame: frame, x: x, y: y))
            }
        }
        hatKeys.sort { $0.frame < $1.frame }
        try decode(png)
        for r in rects where r.minX < 0 || r.minY < 0 || Int(r.maxX) > width || Int(r.maxY) > height {
            throw AgentSpritesError.invalid("frame lies outside the sheet")
        }
    }

    private mutating func decode(_ png: Data) throws {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw AgentSpritesError.invalid("sheet png does not decode")
        }
        width = image.width
        height = image.height
        raw = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = raw.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(
                data: buf.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn, width > 0, height > 0 else { throw AgentSpritesError.invalid("sheet png cannot be read") }
    }

    func uniformSize(what: String) throws -> (Int, Int) {
        guard let first = rects.first, first.width > 0, first.height > 0,
              rects.allSatisfy({ $0.size == first.size }) else {
            throw AgentSpritesError.invalid("\(what)s must all be the same size")
        }
        return (Int(first.width), Int(first.height))
    }

    func face(_ index: Int) -> Data {
        let r = rects[index]
        let (x0, y0, w, h) = (Int(r.minX), Int(r.minY), Int(r.width), Int(r.height))
        let scale = AgentSprites.scale
        var out = Data(capacity: w * h * scale * scale * 3)
        for y in 0..<(h * scale) {
            for x in 0..<(w * scale) {
                let o = ((y0 + y / scale) * width + x0 + x / scale) * 4
                let a = raw[o + 3]
                var rgb = (raw[o], raw[o + 1], raw[o + 2])
                if a > 0 && a < 255 {
                    let unmul = { (c: UInt8) -> UInt8 in UInt8(min(255, Int(c) * 255 / Int(a))) }
                    rgb = (unmul(rgb.0), unmul(rgb.1), unmul(rgb.2))
                }
                out.append(contentsOf: FaceRenderer.pack(r: rgb.0, g: rgb.1, b: rgb.2, a: a))
            }
        }
        return out
    }
}
