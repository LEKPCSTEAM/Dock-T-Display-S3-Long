import Foundation
import Testing
@testable import LongDeckCore

private func seq(_ from: UInt8, _ count: Int) -> Data {
    Data((0..<count).map { from &+ UInt8($0) })
}

private let ks = DeckCrypto.unhex("f30b85454b252c5c01eb34d0352494ace01b9084a912da17aa6c413bb797f9cf")!
private let pressBody = #"{"id":"k1","kind":"tap"}"#

private func json(_ text: String) -> [String: Any] {
    try! JSONSerialization.jsonObject(with: Data(text.utf8)) as! [String: Any]
}

@Test func sealMatchesVector() {
    var sealer = FrameSealer(sessionKey: ks)
    let obj = json(sealer.seal(type: "press", body: pressBody))
    #expect(obj["t"] as? String == "press")
    #expect(obj["s"] as? Int == 1)
    #expect(obj["b"] as? String == pressBody)
    #expect(obj["m"] as? String == "8af257832884a4edc1f300cf890aed11f0311e20987315e2498ab218314292bd")
}

@Test func faceChunksSinglePixelMatchesVector() {
    var sealer = FrameSealer(sessionKey: seq(1, 32))
    let frames = sealer.faceChunks(id: 1, w: 1, h: 1, pixels: Data([0xf8, 0x00, 0xff]))
    #expect(frames.count == 1)
    let f = frames[0]
    #expect(f[0] == 0x46)
    #expect(Array(f[1..<5]) == [1, 0, 0, 0])
    #expect(DeckCrypto.hex(f[5..<37]) == "86bd1fd5de4300ce41a05a415509242569b7c27f9035f759cfc6545f4d63c5e3")
    #expect(DeckCrypto.hex(f[37...]) == "01000100010000000100f800ff")
}

@Test func faceChunksSplitsLargeFace() {
    var sealer = FrameSealer(sessionKey: ks)
    let pixels = Data(count: 74 * 84 * 3)
    let frames = sealer.faceChunks(id: 7, w: 74, h: 84, pixels: pixels)
    #expect(frames.count == 2)
    var rows = 0
    for (i, f) in frames.enumerated() {
        let payload = f[37...]
        #expect(payload.count <= 12 * 1024)
        let p = Array(payload)
        #expect(Int(p[8]) | Int(p[9]) << 8 == Int(p[8]) | Int(p[9]) << 8)
        #expect(Int(p[6]) | Int(p[7]) << 8 == rows)
        rows += Int(p[8]) | Int(p[9]) << 8
        #expect(UInt32(f[1]) | UInt32(f[2]) << 8 == UInt32(i + 1))
    }
    #expect(rows == 84)
}

@Test func openerRoundTripsAndRejectsReplay() throws {
    var sealer = FrameSealer(sessionKey: ks)
    var opener = FrameOpener(sessionKey: ks)
    let text = sealer.seal(type: "press", body: pressBody)
    let opened = try opener.open(text)
    #expect(opened.type == "press")
    #expect(opened.body == pressBody)
    #expect(throws: FrameError.replay) { try opener.open(text) }
}

@Test func openerRejectsOtherSessionKey() {
    var sealer = FrameSealer(sessionKey: seq(1, 32))
    var opener = FrameOpener(sessionKey: ks)
    let text = sealer.seal(type: "press", body: pressBody)
    #expect(throws: FrameError.badMac) { try opener.open(text) }
}

@Test func openerRejectsTamperedBody() {
    var sealer = FrameSealer(sessionKey: ks)
    var opener = FrameOpener(sessionKey: ks)
    let text = sealer.seal(type: "press", body: pressBody)
    let tampered = text.replacingOccurrences(of: "tap", with: "long")
    #expect(throws: FrameError.badMac) { try opener.open(tampered) }
}

@Test func openerRejectsMalformed() {
    var opener = FrameOpener(sessionKey: ks)
    #expect(throws: FrameError.malformed) { try opener.open("not json") }
}
