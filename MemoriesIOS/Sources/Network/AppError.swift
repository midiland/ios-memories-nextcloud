import Foundation

/// Errors shown to the user (messages in French).
enum AppError: LocalizedError, Equatable {
    case invalidURL
    case serverUnreachable(String)
    case memoriesNotInstalled
    case serverTooOld(version: String)
    case unexpectedStatus(Int)
    case invalidResponse
    case loginFlowUnavailable(Int)
    case loginTimeout
    case notAuthenticated
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Adresse de serveur invalide."
        case .serverUnreachable(let detail):
            return "Serveur injoignable. Vérifiez l'adresse et votre connexion.\n(\(detail))"
        case .memoriesNotInstalled:
            return "L'app Memories n'est pas installée ou pas activée sur ce serveur Nextcloud."
        case .serverTooOld(let version):
            return "Memories \(version) est trop ancien. Version \(AppConstants.minServerVersion) ou plus récente requise."
        case .unexpectedStatus(let code):
            return "Réponse inattendue du serveur (HTTP \(code))."
        case .invalidResponse:
            return "Réponse du serveur illisible."
        case .loginFlowUnavailable(let code):
            return "Le Login Flow Nextcloud a répondu HTTP \(code). Vérifiez la configuration du reverse proxy (overwriteprotocol)."
        case .loginTimeout:
            return "Délai de connexion dépassé. Veuillez réessayer."
        case .notAuthenticated:
            return "Session expirée ou révoquée. Veuillez vous reconnecter."
        case .keychain(let status):
            return "Erreur du trousseau iOS (\(status))."
        }
    }

    /// Converts a `URLSession` network error into an app error.
    static func from(_ error: Error) -> AppError {
        if let appError = error as? AppError { return appError }
        return .serverUnreachable(error.localizedDescription)
    }
}
