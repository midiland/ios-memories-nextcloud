import Foundation

/// Offline-mode errors (all of them trigger a fallback to remote loading).
enum OfflineError: Error {
    case noManifest
    case integrity(String)
    case download(String, Int)
}
