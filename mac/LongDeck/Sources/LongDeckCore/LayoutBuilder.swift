import Foundation

public struct BuiltLayout {
    public let json: String
    public let hash: String
    public let faces: [UInt16: (w: UInt16, h: UInt16, pixels: Data)]
}

public enum LayoutBuilder {
    public static func build(
        _ config: DeckConfig, render: (KeyConfig) -> Data = FaceRenderer.render,
        sprites: AgentSprites? = nil
    ) -> BuiltLayout {
        var faces: [UInt16: (w: UInt16, h: UInt16, pixels: Data)] = [:]
        var nextFace: UInt16 = 1
        var pages: [[String: Any]] = []
        for page in config.pages {
            var widgets: [[String: Any]] = []
            for k in page.keys {
                let (fw, fh) = FaceRenderer.faceSize(w: k.w, h: k.h)
                faces[nextFace] = (UInt16(fw), UInt16(fh), render(k))
                widgets.append([
                    "id": k.id, "type": "key", "col": k.col, "row": k.row, "w": k.w, "h": k.h,
                    "face": Int(nextFace), "long": k.longAction != nil,
                ])
                nextFace += 1
            }
            for l in page.live {
                var widget: [String: Any] = [
                    "id": l.id, "col": l.col, "row": l.row, "w": l.w, "h": l.h, "face": 0,
                ]
                switch l.kind {
                case .stat(let metric, let style):
                    widget["type"] = "stat"
                    widget["metric"] = metric.rawValue
                    widget["style"] = style.rawValue
                case .volume: widget["type"] = "volume"
                case .clock: widget["type"] = "clock"
                case .claudeSessions: widget["type"] = "claude_sessions"
                case .claudeUsage: widget["type"] = "claude_usage"
                case .claudeAgents: widget["type"] = "claude_agents"
                }
                widgets.append(widget)
            }
            pages.append(["name": page.name, "widgets": widgets])
        }

        var root: [String: Any] = ["pages": pages]
        let hasAgents = config.pages.contains { $0.live.contains { $0.kind == .claudeAgents } }
        if hasAgents, let sprites, nextFace <= spriteFirstId {
            root["agent_sprites"] = addSprites(sprites, to: &faces)
        }

        let body = serialize(root)
        var material = Data(body.utf8)
        for id in faces.keys.sorted() { material.append(faces[id]!.pixels) }
        let hash = String(DeckCrypto.hex(DeckCrypto.sha256(material)).prefix(16))
        let json = "{\"hash\":\"\(hash)\"," + body.dropFirst()
        return BuiltLayout(json: json, hash: hash, faces: faces)
    }

    private static let spriteFirstId: UInt16 = 129

    private static func addSprites(
        _ s: AgentSprites, to faces: inout [UInt16: (w: UInt16, h: UInt16, pixels: Data)]
    ) -> [String: Any] {
        for (i, pixels) in s.frames.enumerated() {
            faces[spriteFirstId + UInt16(i)] = (UInt16(s.frameW), UInt16(s.frameH), pixels)
        }
        let hatFirst = spriteFirstId + UInt16(s.frames.count)
        for (i, pixels) in s.hats.enumerated() {
            faces[hatFirst + UInt16(i)] = (UInt16(s.hatW), UInt16(s.hatH), pixels)
        }
        return [
            "w": s.frameW, "h": s.frameH, "first": Int(spriteFirstId),
            "tags": s.tagRanges.map { [$0.lowerBound, $0.count] },
            "ms": s.durationsMs, "hx": s.hatX, "hy": s.hatY,
            "hats": [Int(hatFirst), s.hats.count], "hw": s.hatW, "hh": s.hatH,
        ]
    }

    private static func serialize(_ object: [String: Any]) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }
}
