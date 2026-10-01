import Foundation

/// A source of device photos shown in the timeline (`LocalFolderConfig` in `src/native/config.ts`).
/// Android lists media folders; iOS has none, so the sources are the whole library and the albums.
struct LocalFolder: Codable, Equatable, Sendable {
    /// Whole photo library.
    static let libraryId = "library"

    let id: String
    let name: String
    var enabled: Bool

    /// Available folders with the user's choices applied. Unknown folders keep their default:
    /// the whole library is enabled, albums are not.
    static func merge(available: [LocalFolder], saved: [LocalFolder]) -> [LocalFolder] {
        let choices = Dictionary(saved.map { ($0.id, $0.enabled) }, uniquingKeysWith: { first, _ in first })
        return available.map { folder in
            var folder = folder
            folder.enabled = choices[folder.id] ?? (folder.id == libraryId)
            return folder
        }
    }
}
