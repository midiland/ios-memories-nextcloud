import Foundation

/// A memory ready to be shown: one thumbnail and the context to caption and open it.
struct MemoryEntry: Codable, Equatable {
    let fileid: Int64
    /// Day id of the photo (when it was taken), to open the timeline on that day.
    let dayid: Int
    /// Anniversary shown in the caption ("3 years ago").
    let yearsAgo: Int
    /// Thumbnail file name inside the cache's `images/` folder.
    let imageName: String
}

/// Memories prepared for the widget, in a folder shared between the app and the widget.
///
/// The app writes (`MemoryRefresher`), the widget only reads: it never sees the credentials.
/// Entries are keyed by the day they are displayed on, so a few days can be prepared ahead
/// and the widget stays useful when a background refresh is skipped.
///
/// Layout: `<root>/onthisday/{index.json, images/<name>}`. This file is shared with the widget
/// target, so it must stay free of app-only dependencies.
struct MemoryCache {
    /// App Group shared by the app and the widget.
    static let appGroup = "group.fr.midiland.memories"

    private struct Index: Codable {
        var version = 1
        /// Display day id (as a string, JSON keys) → memories shown that day.
        var days: [String: [MemoryEntry]] = [:]
    }

    private let fileManager = FileManager.default
    private let directory: URL

    /// `root` defaults to the App Group container. Without it (no entitlement, e.g. a simulator
    /// build signed ad hoc) the cache falls back to the app's own Application Support folder,
    /// which the widget cannot read: it then shows its empty state.
    init(root: URL? = nil) {
        let base = root
            ?? FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroup)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = base.appendingPathComponent("onthisday", isDirectory: true)
    }

    private var indexURL: URL { directory.appendingPathComponent("index.json") }
    private var imagesURL: URL { directory.appendingPathComponent("images", isDirectory: true) }

    /// Thumbnail file name of a photo.
    static func imageName(fileid: Int64) -> String { "\(fileid).jpg" }

    // MARK: - Read

    /// Memories to show on `dayId`; empty when nothing was prepared for that day.
    func entries(forDay dayId: Int) -> [MemoryEntry] {
        readIndex().days[String(dayId)] ?? []
    }

    /// Whether memories are already prepared for `dayId` (an empty list counts: "nothing that day").
    func hasDay(_ dayId: Int) -> Bool {
        readIndex().days[String(dayId)] != nil
    }

    func imageURL(for entry: MemoryEntry) -> URL {
        imagesURL.appendingPathComponent(entry.imageName)
    }

    // MARK: - Write

    /// Stores the thumbnails first, then publishes the index atomically, so a reader never
    /// sees an entry whose image is missing. Days already prepared are replaced, the others kept.
    func store(days: [Int: [MemoryEntry]], images: [String: Data]) throws {
        try fileManager.createDirectory(at: imagesURL, withIntermediateDirectories: true)
        for (name, data) in images {
            try data.write(to: imagesURL.appendingPathComponent(name), options: .atomic)
        }
        var index = readIndex()
        for (dayId, entries) in days { index.days[String(dayId)] = entries }
        try JSONEncoder().encode(index).write(to: indexURL, options: .atomic)
        excludeFromBackup()
    }

    /// Drops the days before `dayId` and every thumbnail no remaining entry uses.
    func prune(before dayId: Int) {
        var index = readIndex()
        index.days = index.days.filter { (Int($0.key) ?? 0) >= dayId }
        try? JSONEncoder().encode(index).write(to: indexURL, options: .atomic)

        let used = Set(index.days.values.flatMap { $0 }.map(\.imageName))
        let files = (try? fileManager.contentsOfDirectory(atPath: imagesURL.path)) ?? []
        for name in files where !used.contains(name) {
            try? fileManager.removeItem(at: imagesURL.appendingPathComponent(name))
        }
    }

    /// Removes everything (logout, remote wipe).
    func removeAll() {
        try? fileManager.removeItem(at: directory)
    }

    // MARK: - Private

    private func readIndex() -> Index {
        guard let data = try? Data(contentsOf: indexURL),
              let index = try? JSONDecoder().decode(Index.self, from: data),
              index.version == 1
        else { return Index() }
        return index
    }

    /// The thumbnails are personal data that can be downloaded again: keep them out of backups.
    private func excludeFromBackup() {
        var url = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }
}
