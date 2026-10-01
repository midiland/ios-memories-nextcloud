import Foundation

/// User choices for device photos, stored in `UserDefaults`:
/// opt-in (`/api/config/allow_media/{0|1}`) and the folders shown (`configSetLocalFolders`).
struct LocalPhotoSettings: Sendable {
    private let enabledKey = "photos.enabled"
    private let foldersKey = "nativex.localFolders"

    private var defaults: UserDefaults { .standard }

    /// The user allowed device photos in the timeline (independent of the iOS permission).
    var isEnabled: Bool {
        get { defaults.bool(forKey: enabledKey) }
        nonmutating set { defaults.set(newValue, forKey: enabledKey) }
    }

    /// Folder choices as saved by the frontend.
    var savedFolders: [LocalFolder] {
        get {
            guard let data = defaults.string(forKey: foldersKey)?.data(using: .utf8),
                  let folders = try? JSONDecoder().decode([LocalFolder].self, from: data)
            else { return [] }
            return folders
        }
        nonmutating set {
            let data = (try? JSONEncoder().encode(newValue)) ?? Data("[]".utf8)
            defaults.set(String(data: data, encoding: .utf8), forKey: foldersKey)
        }
    }

    /// Saves the JSON sent by `configSetLocalFolders`; invalid JSON is ignored.
    func saveFolders(json: String) {
        guard let data = json.data(using: .utf8),
              let folders = try? JSONDecoder().decode([LocalFolder].self, from: data)
        else { return }
        savedFolders = folders
    }
}
