import CryptoKit
import Foundation

/// Télécharge un snapshot complet (équivalent de `AssetSyncCoordinator.syncBlocking`) :
/// - JS vérifiés par SHA-256 (le manifeste lui-même est signé) ;
/// - fichiers inchangés recopiés depuis le snapshot précédent ;
/// - 8 téléchargements en parallèle au plus ;
/// - marqueur `.ready` écrit en dernier, puis nettoyage des anciens snapshots.
struct AssetSyncer {
    typealias Progress = @MainActor (_ done: Int, _ total: Int) -> Void

    let credentials: Credentials
    private let store = SnapshotStore()
    private let maxParallel = 8

    private struct DownloadItem {
        let url: URL
        let destination: URL
        let sha256: String?
    }

    /// Télécharge (si besoin) le snapshot décrit par `manifest` et le renvoie prêt à servir.
    func sync(_ manifest: AssetManifest, progress: @escaping Progress) async throws -> Snapshot {
        let server = credentials.server
        let directory = store.directory(for: server, key: manifest.key)
        if let ready = store.snapshot(at: directory) { return ready }

        let previous = store.latest(for: server)
        try store.prepareEmptyDirectory(directory)
        let target = Snapshot(directory: directory, manifest: manifest)

        let tasks = try planDownloads(manifest, into: target, reusing: previous)
        await progress(0, tasks.count)
        try await download(tasks, progress: progress)

        try store.markReady(directory, manifest: manifest)
        store.prune(server: server, keeping: manifest.key)
        return target
    }

    // MARK: - Planification

    /// Liste les fichiers à télécharger ; recopie ceux qui n'ont pas changé.
    private func planDownloads(
        _ manifest: AssetManifest, into target: Snapshot, reusing previous: Snapshot?
    ) throws -> [DownloadItem] {
        let fileManager = FileManager.default
        let previousHashes = Dictionary(
            (previous?.manifest.js ?? []).map { ($0.name, $0.sha256) }, uniquingKeysWith: { first, _ in first }
        )
        // Le CSS n'a pas d'empreinte : réutilisable seulement si la liste entière est identique.
        let reuseCSS = previous.map { $0.manifest.css.map(\.href) == manifest.css.map(\.href) } ?? false

        var tasks: [DownloadItem] = []
        for asset in manifest.js {
            let destination = target.jsDirectory.appendingPathComponent(asset.name)
            if let previous, previousHashes[asset.name] == asset.sha256,
               (try? fileManager.copyItem(at: previous.jsDirectory.appendingPathComponent(asset.name), to: destination)) != nil {
                continue
            }
            tasks.append(DownloadItem(url: try absoluteURL(asset.href), destination: destination, sha256: asset.sha256))
        }
        for asset in manifest.css {
            let destination = target.cssDirectory.appendingPathComponent(asset.name)
            if reuseCSS, let previous,
               (try? fileManager.copyItem(at: previous.cssDirectory.appendingPathComponent(asset.name), to: destination)) != nil {
                continue
            }
            tasks.append(DownloadItem(url: try absoluteURL(asset.href), destination: destination, sha256: nil))
        }
        return tasks
    }

    /// `href` relatif → origine du serveur + `href` ; les URLs absolues passent telles quelles.
    private func absoluteURL(_ href: String) throws -> URL {
        let text = href.hasPrefix("http://") || href.hasPrefix("https://")
            ? href
            : credentials.server.origin.absoluteString + href
        guard let url = URL(string: text) else { throw OfflineError.download(href, 0) }
        return url
    }

    // MARK: - Téléchargement

    private func download(_ tasks: [DownloadItem], progress: @escaping Progress) async throws {
        var done = 0
        try await withThrowingTaskGroup(of: Void.self) { group in
            var iterator = tasks.makeIterator()
            for _ in 0..<min(maxParallel, tasks.count) {
                if let task = iterator.next() { group.addTask { try await fetch(task) } }
            }
            while try await group.next() != nil {
                done += 1
                await progress(done, tasks.count)
                if let task = iterator.next() { group.addTask { try await fetch(task) } }
            }
        }
    }

    /// Télécharge un fichier, vérifie son SHA-256 éventuel et l'écrit atomiquement.
    private func fetch(_ task: DownloadItem) async throws {
        var request = URLRequest(url: task.url)
        request.setValue(AppConstants.userAgentSuffix, forHTTPHeaderField: "User-Agent")
        if task.url.host == credentials.server.host {
            request.setValue(credentials.basicAuthHeader, forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw OfflineError.download(task.url.lastPathComponent, status) }

        if let expected = task.sha256 {
            let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard actual.caseInsensitiveCompare(expected) == .orderedSame else {
                throw OfflineError.integrity(task.destination.lastPathComponent)
            }
        }
        try data.write(to: task.destination, options: .atomic)
    }
}
