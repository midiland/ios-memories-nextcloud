import Foundation

/// Constantes globales de l'app.
enum AppConstants {
    /// Version minimale de Memories côté serveur (même valeur que `min_server_version` sur Android).
    static let minServerVersion = "9.0.0-rc.1"

    /// Version de l'app (CFBundleShortVersionString).
    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// Suffixe ajouté au User-Agent de la WebView et des requêtes natives.
    ///
    /// ⚠️ Volontairement PAS `MemoriesNative/<v>` : ce marqueur fait basculer le serveur en
    /// mode « app native » (template sans sidebar, pas de préchargement des jours…), ce qui
    /// suppose que `window.nativex` existe. À remplacer quand le pont NativeX sera en place.
    static var userAgentSuffix: String { "MemoriesIOS/\(appVersion)" }

    /// Intervalle et durée max du polling Login Flow v2 (identiques à Android : 3 s / 10 min).
    static let loginPollInterval: UInt64 = 3_000_000_000
    static let loginPollTimeout: TimeInterval = 10 * 60
}
