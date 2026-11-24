import CryptoKit
import Foundation
import Testing
@testable import LongDeckCore

private func seq(_ from: UInt8, _ count: Int) -> Data {
    Data((0..<count).map { from &+ UInt8($0) })
}

private let k = seq(1, 32)
private let boardNonce = seq(0x10, 16)
private let appNonce = seq(0x20, 16)
private let boardId = "aabbccddeeff"
private let appProofHex = "d8553dc93579ca07ca09ceaced0ae03beb2f50cbc05a811b84eae10a3d578adc"
private let boardProofHex = "be8865b415254711f8712bac2543ea4f52fa39e8ccfd18e40dac9c5180cb4647"
private let ksHex = "f30b85454b252c5c01eb34d0352494ace01b9084a912da17aa6c413bb797f9cf"

private func challenge(paired: Bool) -> String {
    #"{"t":"challenge","v":1,"nonce":"\#(DeckCrypto.hex(boardNonce))","paired":\#(paired),"id":"\#(boardId)"}"#
}

private func obj(_ text: String) -> [String: Any] {
    try! JSONSerialization.jsonObject(with: Data(text.utf8)) as! [String: Any]
}

private func sent(_ out: [HandshakeOutput]) -> [[String: Any]] {
    out.compactMap { if case .send(let s) = $0 { return obj(s) } else { return nil } }
}

private func makeHandshake(
    stored: [String: Data] = [:],
    pair: (Curve25519.KeyAgreement.PrivateKey, Data)? = nil
) -> DeckHandshake {
    DeckHandshake(
        storedKey: { stored[$0] },
        random: { n in seq(0x20, n) },
        keyPair: {
            if let pair { return pair }
            let kp = DeckCrypto.newKeyPair()
            return (kp.priv, kp.pub)
        })
}

@Test func startSendsHello() {
    var hs = makeHandshake()
    let frames = sent(hs.start())
    #expect(frames.count == 1)
    #expect(frames[0]["t"] as? String == "hello")
    #expect(frames[0]["v"] as? Int == 1)
    #expect(frames[0]["nonce"] as? String == DeckCrypto.hex(appNonce))
}

@Test func pairedBoardYieldsAuthThenReady() {
    var hs = makeHandshake(stored: [boardId: k])
    _ = hs.start()
    let frames = sent(hs.receive(challenge(paired: true)))
    #expect(frames.count == 1)
    #expect(frames[0]["t"] as? String == "auth")
    #expect(frames[0]["proof"] as? String == appProofHex)
    let out = hs.receive(#"{"t":"auth_ok","proof":"\#(boardProofHex)"}"#)
    #expect(out == [.ready(sessionKey: DeckCrypto.unhex(ksHex)!, boardId: boardId)])
}

@Test func badBoardProofFails() {
    var hs = makeHandshake(stored: [boardId: k])
    _ = hs.start()
    _ = hs.receive(challenge(paired: true))
    let bad = String(repeating: "0", count: 64)
    #expect(hs.receive(#"{"t":"auth_ok","proof":"\#(bad)"}"#) == [.failed("auth")])
}

@Test func unknownBoardAsksToPair() throws {
    let app = DeckCrypto.newKeyPair()
    let board = DeckCrypto.newKeyPair()
    var hs = makeHandshake(pair: (app.priv, app.pub))
    _ = hs.start()
    #expect(hs.receive(challenge(paired: false)).isEmpty)
    let start = sent(hs.beginPairing())
    #expect(start.count == 1)
    #expect(start[0]["t"] as? String == "pair_start")
    #expect(start[0]["pub"] as? String == DeckCrypto.hex(app.pub))
    #expect(hs.receive(#"{"t":"pair_pub","pub":"\#(DeckCrypto.hex(board.pub))"}"#) == [.needPairCode])
}

@Test func pairCodeMismatchFails() {
    let app = DeckCrypto.newKeyPair()
    let board = DeckCrypto.newKeyPair()
    var hs = makeHandshake(pair: (app.priv, app.pub))
    _ = hs.start()
    _ = hs.receive(challenge(paired: false))
    _ = hs.beginPairing()
    _ = hs.receive(#"{"t":"pair_pub","pub":"\#(DeckCrypto.hex(board.pub))"}"#)
    let shared = try! DeckCrypto.shared(priv: app.priv, peerPub: board.pub)
    let kp = DeckCrypto.deriveKey(shared: shared, boardPub: board.pub, appPub: app.pub)
    let right = DeckCrypto.pairCodeString(key: kp)
    let wrong = right == "000000" ? "000001" : "000000"
    #expect(hs.submitPairCode(wrong) == [.failed("code")])
}

@Test func pairCodeMatchSendsConfirmThenAuth() throws {
    let app = DeckCrypto.newKeyPair()
    let board = DeckCrypto.newKeyPair()
    var hs = makeHandshake(pair: (app.priv, app.pub))
    _ = hs.start()
    _ = hs.receive(challenge(paired: false))
    _ = hs.beginPairing()
    _ = hs.receive(#"{"t":"pair_pub","pub":"\#(DeckCrypto.hex(board.pub))"}"#)
    let shared = try DeckCrypto.shared(priv: app.priv, peerPub: board.pub)
    let kp = DeckCrypto.deriveKey(shared: shared, boardPub: board.pub, appPub: app.pub)

    let confirm = sent(hs.submitPairCode(DeckCrypto.pairCodeString(key: kp)))
    #expect(confirm.count == 1)
    #expect(confirm[0]["t"] as? String == "pair_confirm")
    #expect(confirm[0]["proof"] as? String == DeckCrypto.hex(DeckCrypto.confirmProof(key: kp)))

    let out = hs.receive(#"{"t":"pair_ok"}"#)
    #expect(out.count == 2)
    #expect(out[0] == .paired(key: kp, boardId: boardId))
    let auth = sent(Array(out.dropFirst()))
    #expect(auth[0]["t"] as? String == "auth")
    let expected = DeckCrypto.appProof(key: kp, boardNonce: boardNonce, appNonce: appNonce)
    #expect(auth[0]["proof"] as? String == DeckCrypto.hex(expected))
}
