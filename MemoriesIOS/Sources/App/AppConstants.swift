import Foundation

/// Constantes globales de l'app.
enum AppConstants {
    /// Version minimale de Memories côté serveur (même valeur que `min_server_version` sur Android).
    static let minServerVersion = "9.0.0-rc.1"

    /// Version de l'app (CFBundleShortVersionString).
    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// Version du protocole NativeX annoncée au serveur (`MemoriesNative/<v>`).
    /// Alignée sur l'app Android (versionName 1.15) ; le serveur exige ≥ `BinExt::NX_VER_MIN`
    /// (1.1), sinon il renvoie la page « app trop ancienne ».
    static let nativeXVersion = "1.15"

    /// Suffixe ajouté au User-Agent de la WebView et des requêtes natives.
    /// `MemoriesNative/…` fait passer le serveur en mode app native (`Util::callerIsNative`) :
    /// template transparent sans sidebar, pas de préchargement, cookie `nx_auth` accepté.
    static var userAgentSuffix: String { "MemoriesNative/\(nativeXVersion) MemoriesIOS/\(appVersion)" }

    /// Intervalle et durée max du polling Login Flow v2 (identiques à Android : 3 s / 10 min).
    static let loginPollInterval: UInt64 = 3_000_000_000
    static let loginPollTimeout: TimeInterval = 10 * 60
}
