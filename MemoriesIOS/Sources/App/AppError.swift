import Foundation

/// Errors shown to the user. Messages are localized (`Resources/Localizable.xcstrings`).
enum AppError: LocalizedError, Equatable {
    case invalidURL
    case serverUnreachable(String)
    /// The server sent no manifest that parses and verifies: its code is not loaded.
    case noSignedManifest
    /// A downloaded web file does not match the SHA-256 of the signed manifest.
    case webFilesCorrupted
    /// The local server that serves the verified web files could not start.
    case localServerUnavailable
    case memoriesNotInstalled
    case serverTooOld(version: String)
    case unexpectedStatus(Int)
    case invalidResponse
    case loginFlowUnavailable(Int)
    case loginTimeout
    case notAuthenticated
    /// The device was remotely wiped from the Nextcloud settings (Security → Devices & sessions).
    case remoteWipe
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return String(localized: "Invalid server address.")
        case .serverUnreachable(let detail):
            return String(localized: "Server unreachable. Check the address and your connection.\n(\(detail))")
        case .noSignedManifest:
            return String(localized: "The Memories files sent by the server could not be verified, so the app did not load them. Update the app, or contact the server administrator.")
        case .webFilesCorrupted:
            return String(localized: "A Memories file downloaded from the server does not match its signature, so the app did not load it. Try again later, or contact the server administrator.")
        case .localServerUnavailable:
            return String(localized: "The app could not start its internal web server. Try again, or restart the app.")
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
        case .remoteWipe:
            return String(localized: "This device was remotely wiped from Nextcloud. All local data has been erased.")
        case .keychain(let status):
            return String(localized: "iOS Keychain error (\(status)).")
        }
    }

    /// Converts an error into an app error: snapshot errors keep their meaning, anything else
    /// is a transport error (`URLSession`).
    static func from(_ error: Error) -> AppError {
        if let appError = error as? AppError { return appError }
        if let offline = error as? OfflineError {
            switch offline {
            case .noManifest: return .noSignedManifest
            case .integrity: return .webFilesCorrupted
            case .download(_, let status): return status > 0 ? .unexpectedStatus(status) : .invalidResponse
            }
        }
        return .serverUnreachable(error.localizedDescription)
    }
}
