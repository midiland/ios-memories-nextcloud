import Foundation

/// On-disk snapshot storage (equivalent of `AssetCache.kt`):
/// `Application Support/offline/<server>/<SHA-256 key>/{js/, css/, describe.json, .ready}`.
/// A snapshot is only usable with its `.ready` marker. Excluded from iCloud backup
/// (everything can be downloaded again).
struct SnapshotStore {
    private let fileManager = FileManager.default

    private var root: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("offline", isDirectory: true)
    }

    /// Per-server folder: `scheme_host_port`, sanitized into a safe path segment.
    func serverDirectory(for server: ServerURL) -> URL {
        let origin = server.origin
        let raw = "\(origin.scheme ?? "https")_\(origin.host ?? "")\(origin.port.map { "_\($0)" } ?? "")"
        let safe = String(raw.map { $0.isLetter || $0.isNumber || "._-".contains($0) ? $0 : "_" })
        return root.appendingPathComponent(safe, isDirectory: true)
    }

    func directory(for server: ServerURL, key: String) -> URL {
        serverDirectory(for: server).appendingPathComponent(key, isDirectory: true)
    }

    /// Ready snapshot in `directory`, `nil` if incomplete or unreadable.
    func snapshot(at directory: URL) -> Snapshot? {
        guard fileManager.fileExists(atPath: directory.appendingPathComponent(".ready").path),
              let raw = try? Data(contentsOf: directory.appendingPathComponent("describe.json")),
              let manifest = try? AssetManifest(raw: raw)
        else { return nil }
        return Snapshot(directory: directory, manifest: manifest)
    }

    /// Most recent ready snapshot for this server.
    func latest(for server: ServerURL) -> Snapshot? {
        let folder = serverDirectory(for: server)
        let entries = (try? fileManager.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []
        return entries
            .compactMap { snapshot(at: $0) }
            .max { modificationDate($0.directory) < modificationDate($1.directory) }
    }

    /// Prepares an empty folder for a new snapshot.
    func prepareEmptyDirectory(_ directory: URL) throws {
        try? fileManager.removeItem(at: directory)
        for sub in ["js", "css"] {
            try fileManager.createDirectory(
                at: directory.appendingPathComponent(sub, isDirectory: true), withIntermediateDirectories: true
            )
        }
        excludeRootFromBackup()
    }

    /// Finalizes a snapshot: `describe.json`, then the `.ready` marker.
    func markReady(_ directory: URL, manifest: AssetManifest) throws {
        try manifest.raw.write(to: directory.appendingPathComponent("describe.json"), options: .atomic)
        try Data().write(to: directory.appendingPathComponent(".ready"))
    }

    /// Deletes the server's other snapshots (best effort, no errors).
    func prune(server: ServerURL, keeping key: String) {
        let folder = serverDirectory(for: server)
        let entries = (try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for entry in entries where entry.lastPathComponent != key {
            try? fileManager.removeItem(at: entry)
        }
    }

    // MARK: - Private

    private func modificationDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
    }

    private func excludeRootFromBackup() {
        var url = root
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }
}
