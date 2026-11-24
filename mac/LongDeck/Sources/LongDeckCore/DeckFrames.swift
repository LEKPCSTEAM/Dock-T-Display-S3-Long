import Foundation

public enum FrameError: Error, Equatable {
    case badMac
    case replay
    case malformed
}

public struct FrameSealer {
    private let key: Data
    private var seq: UInt32 = 0
    static let maxPayload = 12 * 1024
    static let faceHeader = 10

    public init(sessionKey: Data) {
        key = sessionKey
    }

    public mutating func seal(type: String, body: String) -> String {
        seq += 1
        let mac = DeckCrypto.hmac(key: key, message: Data("\(type)\n\(seq)\n\(body)".utf8))
        let obj: [String: Any] = ["t": type, "s": seq, "b": body, "m": DeckCrypto.hex(mac)]
        let data = try! JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    public mutating func faceChunks(id: UInt16, w: UInt16, h: UInt16, pixels: Data) -> [Data] {
        let rowBytes = Int(w) * 3
        let rowsPerChunk = max(1, (Self.maxPayload - Self.faceHeader) / max(rowBytes, 1))
        var frames: [Data] = []
        var y = 0
        while y < Int(h) {
            let n = min(rowsPerChunk, Int(h) - y)
            var payload = Data()
            for field in [id, w, h, UInt16(y), UInt16(n)] { payload.append(le16(field)) }
            payload.append(pixels.subdata(in: (pixels.startIndex + y * rowBytes)..<(pixels.startIndex + (y + n) * rowBytes)))
            frames.append(sealBinary(payload))
            y += n
        }
        return frames
    }

    private mutating func sealBinary(_ payload: Data) -> Data {
        seq += 1
        let s = le32(seq)
        let mac = DeckCrypto.hmac(key: key, message: s + payload)
        return Data([0x46]) + s + mac + payload
    }
}

public struct FrameOpener {
    private let key: Data
    private var last: UInt32 = 0

    public init(sessionKey: Data) {
        key = sessionKey
    }

    public mutating func open(_ text: String) throws -> (type: String, body: String) {
        guard let obj = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any],
              let t = obj["t"] as? String,
              let sNum = obj["s"] as? NSNumber,
              let b = obj["b"] as? String,
              let m = obj["m"] as? String,
              let mac = DeckCrypto.unhex(m),
              sNum.uint64Value <= UInt64(UInt32.max)
        else { throw FrameError.malformed }
        let s = UInt32(sNum.uint64Value)
        let expected = DeckCrypto.hmac(key: key, message: Data("\(t)\n\(s)\n\(b)".utf8))
        guard constantTimeEqual(mac, expected) else { throw FrameError.badMac }
        guard s > last else { throw FrameError.replay }
        last = s
        return (t, b)
    }
}

func le16(_ v: UInt16) -> Data {
    Data([UInt8(v & 0xff), UInt8(v >> 8)])
}

func le32(_ v: UInt32) -> Data {
    Data((0..<4).map { UInt8((v >> (8 * UInt32($0))) & 0xff) })
}

func constantTimeEqual(_ a: Data, _ b: Data) -> Bool {
    guard a.count == b.count else { return false }
    return zip(a, b).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
}
