import Foundation

/// Downloads a complete snapshot (equivalent of `AssetSyncCoordinator.syncBlocking`):
/// - JS verified by SHA-256, and by size for Memories 10 (the manifest itself is signed);
/// - unchanged files copied from the previous snapshot;
/// - at most 8 parallel downloads;
/// - `.ready` marker written last, then old snapshots are cleaned up.
struct AssetSyncer {
    typealias Progress = @MainActor (_ done: Int, _ total: Int) -> Void

    let credentials: Credentials
    private let store = SnapshotStore()
    private let maxParallel = 8

    private struct DownloadItem {
        let url: URL
        let destination: URL
        let sha256: String?
        /// Expected size in bytes, when the manifest gives one (Memories 10).
        let length: Int?
    }

    /// Downloads (if needed) the snapshot described by `manifest` and returns it ready to serve.
    func sync(_ manifest: AssetManifest, progress: @escaping Progress) async throws -> Snapshot {
        let server = credentials.server
        let directory = store.directory(for: server, key: manifest.key)
        if let ready = store.snapshot(at: directory) { return ready }

        let previous = store.latest(for: server)
        try store.prepareEmptyDirectory(directory)
        let target = Snapshot(directory: directory, manifest: manifest)

        let webPath = await resolveAppWebPath()
        let tasks = try planDownloads(manifest, into: target, reusing: previous, webPath: webPath)
        await progress(0, tasks.count)
        try await download(tasks, progress: progress)

        try store.markReady(directory, manifest: manifest)
        store.prune(server: server, keeping: manifest.key)
        return target
    }

    // MARK: - Planning

    /// Lists the files to download; copies over those that have not changed.
    private func planDownloads(
        _ manifest: AssetManifest, into target: Snapshot, reusing previous: Snapshot?, webPath: AppWebPath
    ) throws -> [DownloadItem] {
        let fileManager = FileManager.default
        let previousHashes = Dictionary(
            (previous?.manifest.js ?? []).map { ($0.name, $0.sha256) }, uniquingKeysWith: { first, _ in first }
        )
        // CSS has no hash: reusable only if the whole list is identical.
        let reuseCSS = previous.map { $0.manifest.css.map(\.href) == manifest.css.map(\.href) } ?? false

        var tasks: [DownloadItem] = []
        for asset in manifest.js {
            let destination = target.jsDirectory.appendingPathComponent(asset.name)
            if let previous, previousHashes[asset.name] == asset.sha256,
               (try? fileManager.copyItem(at: previous.jsDirectory.appendingPathComponent(asset.name), to: destination)) != nil {
                continue
            }
            tasks.append(DownloadItem(
                url: try absoluteURL(webPath.resolve(asset.href)), destination: destination,
                sha256: asset.sha256, length: asset.length
            ))
        }
        for asset in manifest.css {
            let destination = target.cssDirectory.appendingPathComponent(asset.name)
            if reuseCSS, let previous,
               (try? fileManager.copyItem(at: previous.cssDirectory.appendingPathComponent(asset.name), to: destination)) != nil {
                continue
            }
            tasks.append(DownloadItem(url: try absoluteURL(asset.href), destination: destination, sha256: nil, length: nil))
        }
        return tasks
    }

    /// Relative `href` → server origin + `href`; absolute URLs pass through unchanged.
    private func absoluteURL(_ href: String) throws -> URL {
        let text = href.hasPrefix("http://") || href.hasPrefix("https://")
            ? href
            : credentials.server.origin.absoluteString + href
        guard let url = URL(string: text) else { throw OfflineError.download(href, 0) }
        return url
    }

    /// Real location of the app's static files, read from the server's Memories page
    /// (see `AppWebPath`). Falls back to the standard `apps` folder if the page cannot be read.
    private func resolveAppWebPath() async -> AppWebPath {
        let fallback = AppWebPath(webRoot: credentials.server.webRoot)
        guard let url = URL(string: credentials.server.origin.absoluteString + credentials.server.appPath + "/") else {
            return fallback
        }
        do {
            let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url, authorizedFor: credentials))
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let html = String(data: data, encoding: .utf8),
                  let webPath = AppWebPath(pageHTML: html)
            else {
                Log.offline.error("Memories web path not found in its page: using \(fallback.root, privacy: .public)")
                return fallback
            }
            if webPath != fallback {
                Log.offline.info("Memories files served from \(webPath.root, privacy: .public)")
            }
            return webPath
        } catch {
            Log.offline.error("Memories page unavailable: \(String(describing: error), privacy: .public)")
            return fallback
        }
    }

    // MARK: - Download

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

    /// Downloads a file, checks its size and SHA-256 if known, and writes it atomically.
    private func fetch(_ task: DownloadItem) async throws {
        let request = URLRequest(url: task.url, authorizedFor: credentials)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw OfflineError.download(task.url.lastPathComponent, status) }

        if let length = task.length, data.count != length {
            throw OfflineError.integrity(task.destination.lastPathComponent)
        }
        if let expected = task.sha256 {
            guard data.sha256Hex.caseInsensitiveCompare(expected) == .orderedSame else {
                throw OfflineError.integrity(task.destination.lastPathComponent)
            }
        }
        try data.write(to: task.destination, options: .atomic)
    }
}
