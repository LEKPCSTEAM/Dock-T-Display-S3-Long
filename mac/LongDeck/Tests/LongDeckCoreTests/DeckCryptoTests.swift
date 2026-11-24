import CryptoKit
import Foundation
import Testing
@testable import LongDeckCore

private func seq(_ start: UInt8) -> Data {
    Data((0..<32).map { start &+ UInt8($0) })
}

private let key = seq(1)
private let boardNonce = Data((0..<16).map { 0x10 + UInt8($0) })
private let appNonce = Data((0..<16).map { 0x20 + UInt8($0) })

@Suite struct DeckCryptoTests {
    @Test func pairCodeMatchesVector() {
        #expect(DeckCrypto.pairCode(key: key) == 953405)
        #expect(DeckCrypto.pairCodeString(key: key) == "953405")
    }

    @Test func pinHmacMatchesVector() {
        let mac = DeckCrypto.hmac(key: key, message: Data("pin".utf8))
        #expect(DeckCrypto.hex(mac) == "df18efbd810d7116591c8169c19386c2338e3f979e101cf7982afeb933c393ea")
    }

    @Test func appProofMatchesVector() {
        let p = DeckCrypto.appProof(key: key, boardNonce: boardNonce, appNonce: appNonce)
        #expect(DeckCrypto.hex(p) == "d8553dc93579ca07ca09ceaced0ae03beb2f50cbc05a811b84eae10a3d578adc")
    }

    @Test func boardProofMatchesVector() {
        let p = DeckCrypto.boardProof(key: key, appNonce: appNonce, boardNonce: boardNonce)
        #expect(DeckCrypto.hex(p) == "be8865b415254711f8712bac2543ea4f52fa39e8ccfd18e40dac9c5180cb4647")
    }

    @Test func confirmProofMatchesVector() {
        #expect(DeckCrypto.hex(DeckCrypto.confirmProof(key: key)) == "735fdd274a689ef40299136ed2f37ccd6b5be7d8f10b86dbf08eecf8b281fb06")
    }

    @Test func sessionKeyMatchesVector() {
        let ks = DeckCrypto.sessionKey(key: key, boardNonce: boardNonce, appNonce: appNonce)
        #expect(DeckCrypto.hex(ks) == "f30b85454b252c5c01eb34d0352494ace01b9084a912da17aa6c413bb797f9cf")
    }

    @Test func deriveKeyShape() {
        let k = DeckCrypto.deriveKey(shared: Data(repeating: 1, count: 32),
                                     boardPub: Data(repeating: 2, count: 32),
                                     appPub: Data(repeating: 3, count: 32))
        #expect(DeckCrypto.hex(k) == "8a2e491356cfdb05a1d13785e0794d7cd163f91af79a146c976b1d2ac643b679")
    }

    @Test func hexRoundTrip() {
        #expect(DeckCrypto.hex(Data([0x00, 0xab, 0xff])) == "00abff")
        #expect(DeckCrypto.unhex("00abff") == Data([0x00, 0xab, 0xff]))
        #expect(DeckCrypto.unhex("abc") == nil)
        #expect(DeckCrypto.unhex("zz") == nil)
    }

    @Test func x25519MatchesRfc7748() throws {
        let aPriv = try #require(DeckCrypto.unhex("77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a"))
        let bPriv = try #require(DeckCrypto.unhex("5dab087e624a8a4b79e17f8b83800ee66f3bb1292618b6fd1c2f8b27ff88e0eb"))
        let a = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: aPriv)
        let b = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: bPriv)
        #expect(DeckCrypto.hex(a.publicKey.rawRepresentation) == "8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a")
        #expect(DeckCrypto.hex(b.publicKey.rawRepresentation) == "de9edb7d7b7dc1b4d35b61c2ece435373f8343c85b78674dadfc7e146f882b4f")
        let expected = "4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742"
        #expect(DeckCrypto.hex(try DeckCrypto.shared(priv: a, peerPub: b.publicKey.rawRepresentation)) == expected)
        #expect(DeckCrypto.hex(try DeckCrypto.shared(priv: b, peerPub: a.publicKey.rawRepresentation)) == expected)
    }

    @Test func newKeyPairPublicIs32Bytes() {
        let kp = DeckCrypto.newKeyPair()
        #expect(kp.pub.count == 32)
        #expect(kp.pub == kp.priv.publicKey.rawRepresentation)
    }
}
