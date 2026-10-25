import Foundation
import Security

/// Persists credentials whose remote wipe still needs to be confirmed with the server
/// (`POST /core/wipe/success`). The local data is already erased; only the confirmation
/// may have failed (network error). The credentials are kept in the Keychain, under a
/// separate service, so the next launch can retry.
///
/// A pending wipe is only stored after a wipe was actually requested and the local purge
/// already ran — it is never a substitute for the wipe itself.
struct PendingWipeStore {
    private let service: String
    private let account = "pending"

    init(service: String = "fr.midiland.memories.wipe-pending") {
        self.service = service
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    /// Saves the credentials awaiting confirmation. Overwrites any previous pending wipe.
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

    /// The credentials awaiting confirmation, or `nil` when there is none.
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

    /// Forgets the pending wipe (after a successful confirmation, or when giving up).
    func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}
