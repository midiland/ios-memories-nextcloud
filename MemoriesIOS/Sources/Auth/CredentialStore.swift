import Foundation
import Security

/// Persists credentials in the Keychain (never in UserDefaults).
///
/// One account at a time: the item is a `Credentials` JSON under a fixed key.
/// Accessible after first unlock, not synced to iCloud, not migrated
/// to another device.
struct CredentialStore {
    private let service = "gallery.memories.ios.credentials"
    private let account = "default"

    /// Base query identifying the Keychain item.
    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    /// Saves (or replaces) the credentials.
    func save(_ credentials: Credentials) throws {
        let data = try JSONEncoder().encode(credentials)
        SecItemDelete(baseQuery as CFDictionary)

        var query = baseQuery
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw AppError.keychain(status) }
    }

    /// Reads the credentials; `nil` if missing or unreadable.
    func load() -> Credentials? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return try? JSONDecoder().decode(Credentials.self, from: data)
    }

    /// Deletes the credentials (logout).
    func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}
