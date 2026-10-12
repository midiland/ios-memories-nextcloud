import Foundation

/// Offline-mode errors (download and verification of the Memories web files).
enum OfflineError: Error {
    case noManifest
    case integrity(String)
    case download(String, Int)
}
