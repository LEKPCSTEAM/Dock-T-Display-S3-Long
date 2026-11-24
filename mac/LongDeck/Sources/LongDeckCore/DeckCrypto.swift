import CryptoKit
import Foundation

public enum DeckCrypto {
    public static func hmac(key: Data, message: Data) -> Data {
        let mac = HMAC<SHA256>.authenticationCode(for: message, using: SymmetricKey(data: key))
        return Data(mac)
    }

    public static func sha256(_ data: Data) -> Data {
        Data(SHA256.hash(data: data))
    }

    public static func pairCode(key: Data) -> UInt32 {
        let mac = hmac(key: key, message: Data("pin".utf8))
        let word = mac.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        return word % 1_000_000
    }

    public static func pairCodeString(key: Data) -> String {
        String(format: "%06u", pairCode(key: key))
    }

    public static func deriveKey(shared: Data, boardPub: Data, appPub: Data) -> Data {
        sha256(shared + boardPub + appPub)
    }

    public static func sessionKey(key: Data, boardNonce: Data, appNonce: Data) -> Data {
        hmac(key: key, message: Data("session".utf8) + boardNonce + appNonce)
    }

    public static func appProof(key: Data, boardNonce: Data, appNonce: Data) -> Data {
        hmac(key: key, message: Data("app".utf8) + boardNonce + appNonce)
    }

    public static func boardProof(key: Data, appNonce: Data, boardNonce: Data) -> Data {
        hmac(key: key, message: Data("board".utf8) + appNonce + boardNonce)
    }

    public static func confirmProof(key: Data) -> Data {
        hmac(key: key, message: Data("confirm".utf8))
    }

    public static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    public static func unhex(_ string: String) -> Data? {
        let chars = Array(string.utf8)
        guard chars.count % 2 == 0 else { return nil }
        var out = Data(capacity: chars.count / 2)
        for i in stride(from: 0, to: chars.count, by: 2) {
            guard let hi = nibble(chars[i]), let lo = nibble(chars[i + 1]) else { return nil }
            out.append(hi << 4 | lo)
        }
        return out
    }

    private static func nibble(_ c: UInt8) -> UInt8? {
        switch c {
        case 0x30...0x39: return c - 0x30
        case 0x61...0x66: return c - 0x61 + 10
        case 0x41...0x46: return c - 0x41 + 10
        default: return nil
        }
    }

    public static func newKeyPair() -> (priv: Curve25519.KeyAgreement.PrivateKey, pub: Data) {
        let priv = Curve25519.KeyAgreement.PrivateKey()
        return (priv, priv.publicKey.rawRepresentation)
    }

    public static func shared(priv: Curve25519.KeyAgreement.PrivateKey, peerPub: Data) throws -> Data {
        let peer = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: peerPub)
        let secret = try priv.sharedSecretFromKeyAgreement(with: peer)
        return secret.withUnsafeBytes { Data($0) }
    }
}
