import Foundation
import Security

/// Persistance des identifiants dans le Keychain (jamais dans UserDefaults).
///
/// Un seul compte à la fois : l'élément est un JSON `Credentials` sous une clé fixe.
/// Accessible après le premier déverrouillage, non synchronisé iCloud, non migré
/// vers un autre appareil.
struct CredentialStore {
    private let service = "gallery.memories.ios.credentials"
    private let account = "default"

    /// Requête de base identifiant l'élément du trousseau.
    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    /// Enregistre (ou remplace) les identifiants.
    func save(_ credentials: Credentials) throws {
        let data = try JSONEncoder().encode(credentials)
        SecItemDelete(baseQuery as CFDictionary)

        var query = baseQuery
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw AppError.keychain(status) }
    }

    /// Lit les identifiants, `nil` si absents ou illisibles.
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

    /// Supprime les identifiants (déconnexion).
    func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}
