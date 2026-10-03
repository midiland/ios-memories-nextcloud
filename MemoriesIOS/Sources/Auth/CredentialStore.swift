import Foundation
import Security

/// Persists credentials in the Keychain (never in UserDefaults).
///
/// One account at a time: the item is a `Credentials` JSON under a fixed key.
/// Accessible after first unlock, not synced to iCloud, not migrated
/// to another device.
struct CredentialStore {
    private let service: String
    private let account = "default"

    /// `service` identifies the Keychain item; tests use their own so they never touch the real account.
    init(service: String = "fr.midiland.memories.credentials") {
        self.service = service
    }

    /// Base query identifying the Keychain item.
    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    /// Saves (or replaces) the credentials. Updates the existing item in place, so a failure
    /// never leaves the Keychain without credentials.
    func save(_ credentials: Credentials) throws {
        let attributes: [String: Any] = [
            kSecValueData as String: try JSONEncoder().encode(credentials),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        var status = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(baseQuery.merging(attributes) { _, new in new } as CFDictionary, nil)
        }
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
