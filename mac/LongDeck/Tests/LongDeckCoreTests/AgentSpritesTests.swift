import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import LongDeckCore

private typealias RGBA = (r: UInt8, g: UInt8, b: UInt8, a: UInt8)

private func png(width: Int, height: Int, pixel: (Int, Int) -> RGBA) -> Data {
    var raw = [UInt8](repeating: 0, count: width * height * 4)
    for y in 0..<height {
        for x in 0..<width {
            let p = pixel(x, y)
            let o = (y * width + x) * 4
            raw[o] = p.r; raw[o + 1] = p.g; raw[o + 2] = p.b; raw[o + 3] = p.a
        }
    }
    let provider = CGDataProvider(data: Data(raw) as CFData)!
    let image = CGImage(
        width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    let out = NSMutableData()
    let dest = CGImageDestinationCreateWithData(out, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
    return out as Data
}

private func json(_ object: [String: Any]) -> Data {
    try! JSONSerialization.data(withJSONObject: object)
}

private struct Fixture {
    var agentJSON: [String: Any]
    var agentPNG: Data
    var hatsJSON: [String: Any]
    var hatsPNG: Data

    init(fw: Int = 4, fh: Int = 2, counts: [Int] = [2, 1, 1, 1], hats: Int = 8, hatW: Int = 3, hatH: Int = 2,
         pixel: ((Int, Int, Int) -> RGBA)? = nil) {
        let n = counts.reduce(0, +)
        var tags: [[String: Any]] = []
        var from = 0
        for (i, c) in counts.enumerated() {
            tags.append(["name": AgentSprites.tagNames[i], "from": from, "to": from + c - 1])
            from += c
        }
        let frames: [[String: Any]] = (0..<n).map { i in
            ["frame": ["x": i * fw, "y": 0, "w": fw, "h": fh], "duration": 100 + 10 * i]
        }
        let keys: [[String: Any]] = [
            ["frame": 0, "bounds": ["x": 1, "y": 0, "w": 2, "h": 1]],
            ["frame": 2, "bounds": ["x": 2, "y": 1, "w": 2, "h": 1]],
        ]
        agentJSON = ["frames": frames,
                     "meta": ["frameTags": tags, "slices": [["name": "hat", "keys": keys]]]]
        agentPNG = png(width: n * fw, height: fh) { x, y in
            if let pixel { return pixel(x / fw, x % fw, y) }
            let f = x / fw
            return x % fw == 0 && y == 0 ? (255, 0, 0, 255) : (UInt8(f * 8), 100, 200, 255)
        }
        let hatFrames: [[String: Any]] = (0..<hats).map { i in
            ["frame": ["x": i * hatW, "y": 0, "w": hatW, "h": hatH], "duration": 100]
        }
        hatsJSON = ["frames": hatFrames, "meta": ["frameTags": [], "slices": []]]
        hatsPNG = png(width: hats * hatW, height: hatH) { x, _ in (UInt8(x / hatW * 30), 50, 90, 255) }
    }

    func load() throws -> AgentSprites {
        try AgentSprites.load(agentJSON: json(agentJSON), agentPNG: agentPNG,
                              hatsJSON: json(hatsJSON), hatsPNG: hatsPNG)
    }
}

private func stub(_ key: KeyConfig) -> Data { Data([1, 2, 3]) }

private func agentsConfig() -> DeckConfig {
    var c = SampleConfig.dev
    let agents = LiveWidgetConfig(id: "cca", col: 0, row: 0, w: 8, h: 2, kind: .claudeAgents)
    c.pages.append(PageConfig(name: "Agents", keys: [], live: [agents]))
    return c
}

@Suite struct AgentSpritesTests {
    @Test func loadsFixtureSheet() throws {
        let s = try Fixture().load()
        #expect(s.frameW == 12 && s.frameH == 6 && s.hatW == 9 && s.hatH == 6)
        #expect(s.tagRanges == [0..<2, 2..<3, 3..<4, 4..<5])
        #expect(s.durationsMs == [100, 110, 120, 130, 140])
        #expect(s.hatX == [3, 3, 6, 6, 6])
        #expect(s.hatY == [0, 0, 3, 3, 3])
        #expect(s.frames.count == 5 && s.hats.count == 8)
        #expect(s.frames.allSatisfy { $0.count == 12 * 6 * 3 })
        #expect(s.hats.allSatisfy { $0.count == 9 * 6 * 3 })
        #expect(Array(s.frames[0].prefix(3)) == FaceRenderer.pack(r: 255, g: 0, b: 0, a: 255))
        #expect(Array(s.frames[1].prefix(3)) == FaceRenderer.pack(r: 255, g: 0, b: 0, a: 255))
        let offset = (12 * 3 + 3) * 3
        #expect(Array(s.frames[2][offset..<(offset + 3)]) == FaceRenderer.pack(r: 16, g: 100, b: 200, a: 255))
    }

    @Test func nearestNeighbourScale() throws {
        let s = try Fixture(fw: 2, fh: 1) { _, x, _ in x == 0 ? (255, 0, 0, 255) : (0, 0, 255, 255) }.load()
        let red = FaceRenderer.pack(r: 255, g: 0, b: 0, a: 255)
        let blue = FaceRenderer.pack(r: 0, g: 0, b: 255, a: 255)
        let row = Array(repeating: red, count: 3).flatMap { $0 } + Array(repeating: blue, count: 3).flatMap { $0 }
        #expect(s.frameW == 6 && s.frameH == 3)
        #expect(Array(s.frames[0]) == row + row + row)
    }

    @Test func brokenSpritesLoadNil() throws {
        var noTag = Fixture()
        var tags = (noTag.agentJSON["meta"] as! [String: Any])["frameTags"] as! [[String: Any]]
        tags.remove(at: 1)
        var meta = noTag.agentJSON["meta"] as! [String: Any]
        meta["frameTags"] = tags
        noTag.agentJSON["meta"] = meta
        #expect(throws: (any Error).self) { try noTag.load() }

        for hats in [7, 9] {
            #expect(throws: (any Error).self) { try Fixture(hats: hats).load() }
        }
        #expect(throws: (any Error).self) { try Fixture(fw: 25).load() }
        #expect(throws: (any Error).self) { try Fixture(hatW: 25).load() }

        var uneven = Fixture()
        var frames = uneven.agentJSON["frames"] as! [[String: Any]]
        frames[2]["frame"] = ["x": 8, "y": 0, "w": 3, "h": 2]
        uneven.agentJSON["frames"] = frames
        #expect(throws: (any Error).self) { try uneven.load() }

        var corrupt = Fixture()
        #expect(throws: (any Error).self) {
            try AgentSprites.load(agentJSON: Data("{".utf8), agentPNG: corrupt.agentPNG,
                                  hatsJSON: json(corrupt.hatsJSON), hatsPNG: corrupt.hatsPNG)
        }
        corrupt.agentPNG = Data([1, 2, 3])
        #expect(throws: (any Error).self) { try corrupt.load() }

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("longdeck-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(AgentSprites.loadFiles(in: dir) == nil)
    }

    @Test func hatOutsideFrameThrows() {
        var negative = Fixture()
        var meta = negative.agentJSON["meta"] as! [String: Any]
        meta["slices"] = [["name": "hat", "keys": [["frame": 0, "bounds": ["x": -1, "y": 0, "w": 1, "h": 1]]]]]
        negative.agentJSON["meta"] = meta
        #expect(throws: (any Error).self) { try negative.load() }

        var huge = Fixture()
        meta["slices"] = [["name": "hat", "keys": [["frame": 0, "bounds": ["x": 90, "y": 0, "w": 1, "h": 1]]]]]
        huge.agentJSON["meta"] = meta
        #expect(throws: (any Error).self) { try huge.load() }
    }

    @Test func loadFilesReadsDirectory() throws {
        let fx = Fixture()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("longdeck-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try json(fx.agentJSON).write(to: dir.appendingPathComponent("claude-agent.json"))
        try fx.agentPNG.write(to: dir.appendingPathComponent("claude-agent.png"))
        try json(fx.hatsJSON).write(to: dir.appendingPathComponent("claude-hats.json"))
        try fx.hatsPNG.write(to: dir.appendingPathComponent("claude-hats.png"))
        #expect(AgentSprites.loadFiles(in: dir) == (try fx.load()))
    }

    @Test func bundledNeverTraps() {
        _ = AgentSprites.bundled()
    }

    @Test func bundledSpritesLoad() throws {
        let s = try #require(AgentSprites.bundled())
        #expect(s.tagRanges.count == 4)
        #expect(s.tagRanges.map(\.count) == [4, 2, 4, 4])
        #expect(s.hats.count == 8)
        #expect(s.frameW == 60 && s.frameH == 72)
        #expect(s.hatW == 60 && s.hatH == 30)
        #expect(s.hatY.allSatisfy { $0 == 6 })
        // Native (8, 13) of the first working frame is body orange #D97757.
        let at = ((13 * 3 + 1) * s.frameW + (8 * 3 + 1)) * 3
        #expect(Array(s.frames[0][at..<at + 3]) == FaceRenderer.pack(r: 0xD9, g: 0x77, b: 0x57, a: 255))
    }

    @Test func layoutUnchangedWithoutAgentsWidget() throws {
        let s = try Fixture().load()
        let plain = LayoutBuilder.build(SampleConfig.dev, render: stub)
        let with = LayoutBuilder.build(SampleConfig.dev, render: stub, sprites: s)
        #expect(with.json == plain.json)
        #expect(with.hash == plain.hash)
        #expect(with.faces.keys.sorted() == plain.faces.keys.sorted())
        let noSprites = LayoutBuilder.build(agentsConfig(), render: stub)
        #expect(noSprites.json == LayoutBuilder.build(agentsConfig(), render: stub, sprites: nil).json)
        #expect(noSprites.json.contains("agent_sprites") == false)
    }

    @Test func layoutAddsSpriteFacesAndTable() throws {
        let s = try Fixture().load()
        let plain = LayoutBuilder.build(agentsConfig(), render: stub)
        let built = LayoutBuilder.build(agentsConfig(), render: stub, sprites: s)
        #expect(built.hash != plain.hash)
        for id in 129..<(129 + 5 + 8) { #expect(built.faces[UInt16(id)] != nil) }
        #expect(built.faces[142] == nil)
        #expect(built.faces[129]?.w == 12 && built.faces[129]?.h == 6)
        #expect(built.faces[134]?.w == 9 && built.faces[134]?.h == 6)
        #expect(built.faces[129]?.pixels == s.frames[0])
        #expect(built.faces[141]?.pixels == s.hats[7])

        let root = try #require(JSONSerialization.jsonObject(with: Data(built.json.utf8)) as? [String: Any])
        let table = try #require(root["agent_sprites"] as? [String: Any])
        #expect(table["w"] as? Int == 12 && table["h"] as? Int == 6 && table["first"] as? Int == 129)
        #expect(table["tags"] as? [[Int]] == [[0, 2], [2, 1], [3, 1], [4, 1]])
        #expect(table["ms"] as? [Int] == [100, 110, 120, 130, 140])
        #expect(table["hx"] as? [Int] == [3, 3, 6, 6, 6])
        #expect(table["hy"] as? [Int] == [0, 0, 3, 3, 3])
        #expect(table["hats"] as? [Int] == [134, 8])
        #expect(table["hw"] as? Int == 9 && table["hh"] as? Int == 6)
    }

    @Test func spriteTableFitsFrame() throws {
        let s = try Fixture(counts: [8, 8, 8, 8]).load()
        var c = SampleConfig.dev
        c.pages.append(PageConfig(name: "Agents", keys: [], live: [
            LiveWidgetConfig(id: "cca", col: 0, row: 0, w: 8, h: 2, kind: .claudeAgents)]))
        let bytes = LayoutSize.sealedBytes(c, sprites: s)
        #expect(bytes > LayoutSize.sealedBytes(c))
        #expect(LayoutPushPolicy.fits(frameBytes: bytes))
    }

    @Test func issuesCountSprites() throws {
        let s = try Fixture().load()
        var pages: [PageConfig] = []
        for p in 0..<7 {
            var live: [LiveWidgetConfig] = []
            for i in 0..<16 {
                let id = String(format: "s%014d", p * 16 + i)
                live.append(LiveWidgetConfig(id: id, col: i % 8, row: i / 8, w: 1, h: 1,
                                             kind: .stat(.diskFree, .sparkline)))
            }
            pages.append(PageConfig(name: String(format: "P%022d", p), keys: [], live: live))
        }
        pages[0].live.removeFirst(2)
        pages[0].live.append(LiveWidgetConfig(id: "cca", col: 0, row: 0, w: 2, h: 1, kind: .claudeAgents))
        let c = DeckConfig(version: 1, pages: pages)
        let env = IssueEnvironment(fileExists: { _ in true }, symbolExists: { _ in true }, sprites: s)
        let found = EditorIssues.check(c, env).map(\.message).filter { $0.hasPrefix("Layout is") }
        #expect(found.count == 1)
        #expect(found[0].hasPrefix("Layout is \(LayoutSize.sealedBytes(c, sprites: s)) bytes"))
        #expect(LayoutSize.sealedBytes(c, sprites: s) != LayoutSize.sealedBytes(c))
    }
}
