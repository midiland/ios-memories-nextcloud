import Foundation

/// Snapshot prêt à servir : fichiers JS/CSS d'une version de Memories.
struct Snapshot {
    let directory: URL
    let manifest: AssetManifest

    var key: String { directory.lastPathComponent }
    var jsDirectory: URL { directory.appendingPathComponent("js", isDirectory: true) }
    var cssDirectory: URL { directory.appendingPathComponent("css", isDirectory: true) }
}

/// Stockage disque des snapshots (équivalent de `AssetCache.kt`) :
/// `Application Support/offline/<serveur>/<clé SHA-256>/{js/, css/, describe.json, .ready}`.
/// Un snapshot n'est utilisable qu'avec son marqueur `.ready`. Exclu de la sauvegarde iCloud
/// (tout est retéléchargeable).
struct SnapshotStore {
    private let fileManager = FileManager.default

    private var root: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("offline", isDirectory: true)
    }

    /// Dossier d'un serveur : `schéma_hôte_port`, assaini en segment de chemin sûr.
    func serverDirectory(for server: ServerURL) -> URL {
        let origin = server.origin
        let raw = "\(origin.scheme ?? "https")_\(origin.host ?? "")\(origin.port.map { "_\($0)" } ?? "")"
        let safe = String(raw.map { $0.isLetter || $0.isNumber || "._-".contains($0) ? $0 : "_" })
        return root.appendingPathComponent(safe, isDirectory: true)
    }

    func directory(for server: ServerURL, key: String) -> URL {
        serverDirectory(for: server).appendingPathComponent(key, isDirectory: true)
    }

    /// Snapshot prêt dans `directory`, `nil` s'il est incomplet ou illisible.
    func snapshot(at directory: URL) -> Snapshot? {
        guard fileManager.fileExists(atPath: directory.appendingPathComponent(".ready").path),
              let raw = try? Data(contentsOf: directory.appendingPathComponent("describe.json")),
              let manifest = try? AssetManifest(raw: raw)
        else { return nil }
        return Snapshot(directory: directory, manifest: manifest)
    }

    /// Snapshot prêt le plus récent pour ce serveur.
    func latest(for server: ServerURL) -> Snapshot? {
        let folder = serverDirectory(for: server)
        let entries = (try? fileManager.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []
        return entries
            .compactMap { snapshot(at: $0) }
            .max { modificationDate($0.directory) < modificationDate($1.directory) }
    }

    /// Prépare un dossier vide pour un nouveau snapshot.
    func prepareEmptyDirectory(_ directory: URL) throws {
        try? fileManager.removeItem(at: directory)
        for sub in ["js", "css"] {
            try fileManager.createDirectory(
                at: directory.appendingPathComponent(sub, isDirectory: true), withIntermediateDirectories: true
            )
        }
        excludeRootFromBackup()
    }

    /// Finalise un snapshot : `describe.json` puis marqueur `.ready`.
    func markReady(_ directory: URL, manifest: AssetManifest) throws {
        try manifest.raw.write(to: directory.appendingPathComponent("describe.json"), options: .atomic)
        try Data().write(to: directory.appendingPathComponent(".ready"))
    }

    /// Supprime les autres snapshots du serveur (au mieux, sans erreur).
    func prune(server: ServerURL, keeping key: String) {
        let folder = serverDirectory(for: server)
        let entries = (try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for entry in entries where entry.lastPathComponent != key {
            try? fileManager.removeItem(at: entry)
        }
    }

    // MARK: - Privé

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
