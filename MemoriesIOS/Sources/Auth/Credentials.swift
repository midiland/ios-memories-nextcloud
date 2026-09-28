import Foundation

/// Nextcloud account credentials, obtained via Login Flow v2.
/// Stored only in the Keychain (see `CredentialStore`).
struct Credentials: Codable, Equatable {
    /// Root of the Memories app on the server.
    let server: ServerURL
    let loginName: String
    /// App password (revocable from the Nextcloud settings).
    let appPassword: String

    /// Value of the `Authorization: Basic …` header.
    var basicAuthHeader: String {
        let raw = "\(loginName):\(appPassword)"
        return "Basic " + Data(raw.utf8).base64EncodedString()
    }
}
