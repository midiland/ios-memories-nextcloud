import Foundation

/// Errors shown to the user. Messages are localized (`Resources/Localizable.xcstrings`).
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
            return String(localized: "Invalid server address.")
        case .serverUnreachable(let detail):
            return String(localized: "Server unreachable. Check the address and your connection.\n(\(detail))")
        case .memoriesNotInstalled:
            return String(localized: "The Memories app is not installed or not enabled on this Nextcloud server.")
        case .serverTooOld(let version):
            return String(localized: "Memories \(version) is too old. Version \(AppConstants.minServerVersion) or later is required.")
        case .unexpectedStatus(let code):
            return String(localized: "Unexpected server response (HTTP \(code)).")
        case .invalidResponse:
            return String(localized: "Unreadable server response.")
        case .loginFlowUnavailable(let code):
            return String(localized: "Nextcloud Login Flow returned HTTP \(code). Check your reverse proxy configuration (overwriteprotocol).")
        case .loginTimeout:
            return String(localized: "Login timed out. Please try again.")
        case .notAuthenticated:
            return String(localized: "Session expired or revoked. Please sign in again.")
        case .keychain(let status):
            return String(localized: "iOS Keychain error (\(status)).")
        }
    }

    /// Converts a `URLSession` network error into an app error.
    static func from(_ error: Error) -> AppError {
        if let appError = error as? AppError { return appError }
        return .serverUnreachable(error.localizedDescription)
    }
}
