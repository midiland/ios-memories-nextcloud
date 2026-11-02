import Foundation
import Security

/// A remote wipe whose confirmation with the server (`POST /core/wipe/success`)
/// still has to be sent. Only what the wipe endpoints actually need is kept:
/// the server URL and the app password (sent as the `token` form parameter) —
/// never the login name (issue #15 review feedback).
struct PendingWipe: Codable, Equatable {
    let server: ServerURL
    /// The app password: the token itself is the credential on the `#[PublicPage]` wipe endpoints.
    let token: String
    /// How many times the check/confirmation was attempted (and failed) so far.
    var attempts: Int = 0
}

/// Persists a pending remote wipe. The local data is already erased; only the
/// confirmation may have failed (network error). The entry is kept in the
/// Keychain, under a separate service, so the next launch can retry.
///
/// A pending wipe is only stored after a wipe was actually requested and the local
/// purge already ran — it is never a substitute for the wipe itself.
struct PendingWipeStore {
    /// After this many failed attempts the entry is dropped: the token is already
    /// invalidated server-side and the local purge has run, so keeping it forever
    /// would only leave a dead credential in the Keychain (issue #15 review feedback).
    static let maxAttempts = 5

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

    /// Saves the pending wipe. Overwrites any previous pending wipe.
    func save(_ pending: PendingWipe) throws {
        let attributes: [String: Any] = [
            kSecValueData as String: try JSONEncoder().encode(pending),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        var status = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(baseQuery.merging(attributes) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw AppError.keychain(status) }
    }

    /// The pending wipe, or `nil` when there is none.
    func load() -> PendingWipe? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return try? JSONDecoder().decode(PendingWipe.self, from: data)
    }

    /// Forgets the pending wipe (after a successful confirmation, or when giving up).
    func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}
