import Foundation

/// Persists the `ManifestPin` of each account in `UserDefaults` (not secret, small).
struct ManifestPinStore {
    private static let prefix = "manifestPin."
    var defaults: UserDefaults = .standard

    func pin(for credentials: Credentials) -> ManifestPin? {
        guard let data = defaults.data(forKey: key(for: credentials)) else { return nil }
        return try? JSONDecoder().decode(ManifestPin.self, from: data)
    }

    func save(_ pin: ManifestPin?, for credentials: Credentials) {
        guard let pin, let data = try? JSONEncoder().encode(pin) else { return }
        defaults.set(data, forKey: key(for: credentials))
    }

    /// Forgets every account's pin (logout: a new sign-in starts from scratch).
    func removeAll() {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(Self.prefix) {
            defaults.removeObject(forKey: key)
        }
    }

    private func key(for credentials: Credentials) -> String {
        Self.prefix + "\(credentials.loginName)@\(credentials.server.origin.absoluteString)"
    }
}
