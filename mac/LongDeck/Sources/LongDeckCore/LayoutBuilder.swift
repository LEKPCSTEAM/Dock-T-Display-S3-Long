import Foundation

public struct BuiltLayout {
    public let json: String
    public let hash: String
    public let faces: [UInt16: (w: UInt16, h: UInt16, pixels: Data)]
}

public enum LayoutBuilder {
    public static func build(
        _ config: DeckConfig, render: (KeyConfig) -> Data = FaceRenderer.render
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
            pages.append(["name": page.name, "widgets": widgets])
        }

        let body = serialize(["pages": pages])
        var material = Data(body.utf8)
        for id in faces.keys.sorted() { material.append(faces[id]!.pixels) }
        let hash = String(DeckCrypto.hex(DeckCrypto.sha256(material)).prefix(16))
        let json = "{\"hash\":\"\(hash)\"," + body.dropFirst()
        return BuiltLayout(json: json, hash: hash, faces: faces)
    }

    private static func serialize(_ object: [String: Any]) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }
}
