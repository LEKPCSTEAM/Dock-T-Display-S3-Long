import CryptoKit
import Foundation

public enum HandshakeOutput: Equatable {
    case send(String)
    case needPairCode
    case ready(sessionKey: Data, boardId: String)
    case paired(key: Data, boardId: String)
    case failed(String)
}

public struct DeckHandshake {
    private let storedKey: (String) -> Data?
    private let random: (Int) -> Data
    private let keyPair: () -> (Curve25519.KeyAgreement.PrivateKey, Data)

    private var appNonce = Data()
    private var boardNonce = Data()
    private var boardId = ""
    private var key: Data?
    private var appPriv: Curve25519.KeyAgreement.PrivateKey?
    private var appPub = Data()
    private var pendingKey: Data?

    public init(
        storedKey: @escaping (String) -> Data?,
        random: @escaping (Int) -> Data,
        keyPair: @escaping () -> (Curve25519.KeyAgreement.PrivateKey, Data)
    ) {
        self.storedKey = storedKey
        self.random = random
        self.keyPair = keyPair
    }

    public mutating func start() -> [HandshakeOutput] {
        appNonce = random(16)
        return [frame(["t": "hello", "v": 1, "nonce": DeckCrypto.hex(appNonce)])]
    }

    public mutating func receive(_ text: String) -> [HandshakeOutput] {
        guard let obj = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any],
              let t = obj["t"] as? String
        else { return [.failed("malformed")] }
        switch t {
        case "challenge": return onChallenge(obj)
        case "pair_pub": return onPairPub(obj)
        case "pair_ok": return onPairOk()
        case "auth_ok": return onAuthOk(obj)
        case "error": return [.failed(obj["code"] as? String ?? "error")]
        default: return [.failed("malformed")]
        }
    }

    public mutating func beginPairing() -> [HandshakeOutput] {
        let pair = keyPair()
        appPriv = pair.0
        appPub = pair.1
        return [frame(["t": "pair_start", "pub": DeckCrypto.hex(appPub)])]
    }

    public mutating func submitPairCode(_ code: String) -> [HandshakeOutput] {
        guard let pending = pendingKey, code == DeckCrypto.pairCodeString(key: pending) else {
            return [.failed("code")]
        }
        let proof = DeckCrypto.confirmProof(key: pending)
        return [frame(["t": "pair_confirm", "proof": DeckCrypto.hex(proof)])]
    }

    private mutating func onChallenge(_ obj: [String: Any]) -> [HandshakeOutput] {
        guard let nonce = (obj["nonce"] as? String).flatMap(DeckCrypto.unhex),
              let id = obj["id"] as? String
        else { return [.failed("malformed")] }
        boardNonce = nonce
        boardId = id
        guard let stored = storedKey(id) else { return [] }
        key = stored
        return [authFrame(stored)]
    }

    private mutating func onPairPub(_ obj: [String: Any]) -> [HandshakeOutput] {
        guard let priv = appPriv,
              let boardPub = (obj["pub"] as? String).flatMap(DeckCrypto.unhex),
              let shared = try? DeckCrypto.shared(priv: priv, peerPub: boardPub)
        else { return [.failed("malformed")] }
        pendingKey = DeckCrypto.deriveKey(shared: shared, boardPub: boardPub, appPub: appPub)
        return [.needPairCode]
    }

    private mutating func onPairOk() -> [HandshakeOutput] {
        guard let pending = pendingKey else { return [.failed("malformed")] }
        key = pending
        return [.paired(key: pending, boardId: boardId), authFrame(pending)]
    }

    private func onAuthOk(_ obj: [String: Any]) -> [HandshakeOutput] {
        guard let key,
              let proof = (obj["proof"] as? String).flatMap(DeckCrypto.unhex),
              constantTimeEqual(proof, DeckCrypto.boardProof(key: key, appNonce: appNonce, boardNonce: boardNonce))
        else { return [.failed("auth")] }
        let session = DeckCrypto.sessionKey(key: key, boardNonce: boardNonce, appNonce: appNonce)
        return [.ready(sessionKey: session, boardId: boardId)]
    }

    private func authFrame(_ key: Data) -> HandshakeOutput {
        let proof = DeckCrypto.appProof(key: key, boardNonce: boardNonce, appNonce: appNonce)
        return frame(["t": "auth", "proof": DeckCrypto.hex(proof)])
    }

    private func frame(_ obj: [String: Any]) -> HandshakeOutput {
        let data = try! JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])
        return .send(String(decoding: data, as: UTF8.self))
    }
}
