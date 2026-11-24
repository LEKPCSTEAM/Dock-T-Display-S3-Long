import Foundation
import Security

public enum KeyStoreError: Error, Equatable {
    case keychain(OSStatus)
}

public enum KeyStore {
    static let service = "dev.longdeck.LongDeck"

    private static func query(_ boardId: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: boardId,
        ]
    }

    public static func load(boardId: String) -> Data? {
        var q = query(boardId)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }

    public static func save(_ key: Data, boardId: String) throws {
        let update = SecItemUpdate(query(boardId) as CFDictionary,
                                   [kSecValueData as String: key] as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw KeyStoreError.keychain(update) }
        var add = query(boardId)
        add[kSecValueData as String] = key
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeyStoreError.keychain(status) }
    }

    public static func delete(boardId: String) {
        SecItemDelete(query(boardId) as CFDictionary)
    }
}
