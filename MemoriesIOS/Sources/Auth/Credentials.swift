import Foundation

/// Identifiants d'un compte Nextcloud, obtenus via Login Flow v2.
/// Stockés uniquement dans le Keychain (voir `CredentialStore`).
struct Credentials: Codable, Equatable {
    /// Racine de l'app Memories sur le serveur.
    let server: ServerURL
    let loginName: String
    /// Mot de passe d'application (révocable depuis les paramètres Nextcloud).
    let appPassword: String

    /// Valeur du header `Authorization: Basic …`.
    var basicAuthHeader: String {
        let raw = "\(loginName):\(appPassword)"
        return "Basic " + Data(raw.utf8).base64EncodedString()
    }
}
