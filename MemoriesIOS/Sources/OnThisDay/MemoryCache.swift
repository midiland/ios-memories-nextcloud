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
/// Layout: `<root>/onthisday/{index.json, hidden.json, cursor.json, images/<name>}`. This file is shared with the widget
/// target, so it must stay free of app-only dependencies.
struct MemoryCache {
    /// App Group shared by the app and the widget.
    static let appGroup = "group.fr.midiland.memories"

    private struct Index: Codable {
        var version = 1
        /// Display day id (as a string, JSON keys) → memories shown that day.
        var days: [String: [MemoryEntry]] = [:]
    }

    private struct Cursor: Codable {
        let day: Int
        let offset: Int
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
    private var hiddenURL: URL { directory.appendingPathComponent("hidden.json") }
    private var pendingHideURL: URL { directory.appendingPathComponent("pending-hide.json") }
    private var cursorURL: URL { directory.appendingPathComponent("cursor.json") }
    private var imagesURL: URL { directory.appendingPathComponent("images", isDirectory: true) }

    /// Thumbnail file name of a photo.
    static func imageName(fileid: Int64) -> String { "\(fileid).jpg" }

    // MARK: - Read

    /// Memories to show on `dayId`, without the photos the user hid; empty when nothing was
    /// prepared for that day.
    func entries(forDay dayId: Int) -> [MemoryEntry] {
        let hidden = hiddenFileIDs()
        return (readIndex().days[String(dayId)] ?? []).filter { !hidden.contains($0.fileid) }
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

    // MARK: - Hidden photos

    /// Photos the user removed from the widget with its cross.
    func hiddenFileIDs() -> Set<Int64> {
        guard let data = try? Data(contentsOf: hiddenURL),
              let ids = try? JSONDecoder().decode([Int64].self, from: data)
        else { return [] }
        return Set(ids)
    }

    /// How long a "remove this photo?" question stays open.
    static let confirmationTimeout: TimeInterval = 5 * 60

    private struct PendingHide: Codable {
        let fileid: Int64
        let askedAt: Date
    }

    /// The cross was tapped: the widget asks for confirmation before hiding `fileid`.
    func askToHide(fileid: Int64, now: Date = Date()) {
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try? JSONEncoder().encode(PendingHide(fileid: fileid, askedAt: now)).write(to: pendingHideURL, options: .atomic)
    }

    /// The photo the widget is asking about, unless the question is stale (the user walked away).
    func photoAskedToHide(now: Date = Date()) -> Int64? {
        guard let data = try? Data(contentsOf: pendingHideURL),
              let pending = try? JSONDecoder().decode(PendingHide.self, from: data),
              now.timeIntervalSince(pending.askedAt) < Self.confirmationTimeout
        else { return nil }
        return pending.fileid
    }

    /// "Cancel" in the widget.
    func cancelHide() {
        try? fileManager.removeItem(at: pendingHideURL)
    }

    /// Never shows this photo again (the list is erased with the memories on logout or wipe).
    func hide(fileid: Int64) {
        cancelHide()
        var ids = hiddenFileIDs()
        ids.insert(fileid)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try? JSONEncoder().encode(ids.sorted()).write(to: hiddenURL, options: .atomic)
    }

    // MARK: - Cursor

    /// How many memories the user skipped with the widget's "next" button on `dayId`.
    /// Only the widget writes it, so it lives next to the memories and goes with them.
    func cursor(forDay dayId: Int) -> Int {
        guard let data = try? Data(contentsOf: cursorURL),
              let cursor = try? JSONDecoder().decode(Cursor.self, from: data),
              cursor.day == dayId
        else { return 0 }
        return max(0, cursor.offset)
    }

    /// Moves on to the next memory (the cursor restarts at 0 on a new day).
    func advanceCursor(forDay dayId: Int) {
        let cursor = Cursor(day: dayId, offset: self.cursor(forDay: dayId) + 1)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try? JSONEncoder().encode(cursor).write(to: cursorURL, options: .atomic)
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
