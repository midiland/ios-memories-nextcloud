import Foundation

/// Downloads and sharing requested by the web UI
/// (`downloadFromUrl`, `setShareBlobs` + `/api/share/blobs`, `/api/share/url`).
///
/// Android saves downloads to "Downloads" with a notification; on iOS photos and videos (also
/// those of an album ZIP) are saved to Photos, other files go through the share sheet.
@MainActor
final class NativeXShareService {
    /// Object staged by `setShareBlobs` (JSON `[{ auid, href }]`).
    private struct Blob: Decodable {
        let auid: String?
        let href: String
    }

    /// Receives the toasts (download started / failed) and the download progress (issue #14).
    weak var host: NativeXHost?
    private let downloader: any FileDownloading
    private let photoLibrary: PhotoLibrary
    /// Shows the share sheet for files or links.
    private let presentShareSheet: @MainActor ([Any]) -> Void
    private var stagedBlobs: [Blob] = []
    /// The ongoing album download (issue #14), cancelled by `cancelDownload`.
    private var downloadTask: Task<Void, Never>?
    /// Identifies the current download: a cancelled one that finishes late must not hide the
    /// overlay, report progress or clear the task of the one that replaced it.
    private var activeDownloadID: UUID?

    init(
        downloader: any FileDownloading,
        photoLibrary: PhotoLibrary,
        presentShareSheet: @escaping @MainActor ([Any]) -> Void
    ) {
        self.downloader = downloader
        self.photoLibrary = photoLibrary
        self.presentShareSheet = presentShareSheet
    }

    /// `nativex.setShareBlobs(json)`: remembers the files for the next `/api/share/blobs`.
    func stageBlobs(_ json: String?) {
        guard let data = json?.data(using: .utf8),
              let blobs = try? JSONDecoder().decode([Blob].self, from: data)
        else { stagedBlobs = []; return }
        stagedBlobs = blobs
    }

    /// `/api/share/blobs`: downloads the staged files, then opens the share sheet.
    /// Returns only once the downloads are complete (frontend contract).
    func shareStagedBlobs() async -> Bool {
        let blobs = stagedBlobs
        stagedBlobs = []
        guard !blobs.isEmpty else { return false }

        var files: [URL] = []
        for blob in blobs {
            guard let url = URL(string: blob.href) else { continue }
            do {
                files.append(try await downloader.download(url))
            } catch {
                Log.nativex.error("Share download failed: \(String(describing: error), privacy: .public)")
            }
        }
        guard !files.isEmpty else { return false }
        presentShareSheet(files)
        return true
    }

    /// `/api/share/url/…`: shares the link as is, without downloading it.
    func shareLink(_ url: URL) {
        presentShareSheet([url])
    }

    /// `nativex.downloadFromUrl(url, filename, title)`: background download, then Photos (album
    /// named `title`) or the share sheet; toast with the result. A persistent progress overlay
    /// (issue #14) shows the download → extract → save phases.
    func download(urlString: String?, filename: String?, title: String?) {
        guard let urlString, let url = URL(string: urlString), let host else { return }
        // One download at a time: a new request replaces (and cancels) the previous one.
        downloadTask?.cancel()
        let id = UUID()
        activeDownloadID = id

        if let title, !title.isEmpty {
            host.nativeXToast(String(localized: "Downloading \(title)…"), long: false)
        } else {
            host.nativeXToast(String(localized: "Downloading…"), long: false)
        }

        // Show the persistent progress overlay (issue #14).
        host.nativeXSetDownloadProgress(.init(phase: .downloading, done: 0, total: 0, title: title))

        let name = filename?.isEmpty == false ? filename : nil
        downloadTask = Task { [weak self] in
            guard let self else { return }
            var folder: URL?
            do {
                // Phase 1: download the file (ZIP for an album) with byte progress.
                let file = try await downloader.download(url, preferredName: name) { [weak self] done, total in
                    Task { @MainActor in
                        self?.report(.init(phase: .downloading, done: Int(done), total: Int(total), title: title), for: id)
                    }
                }
                folder = file.deletingLastPathComponent()
                try Task.checkCancellation()
                await saveOrShare(file, album: title, id: id)
            } catch is CancellationError {
                // Cancelled by the user (issue #14) or replaced by a newer download.
                if let folder { try? FileManager.default.removeItem(at: folder) }
            } catch {
                if self.activeDownloadID == id {
                    self.host?.nativeXToast(String(localized: "Download failed: \(error.localizedDescription)"), long: true)
                }
            }
            if self.activeDownloadID == id {
                self.host?.nativeXSetDownloadProgress(nil)
                self.downloadTask = nil
                self.activeDownloadID = nil
            }
        }
    }

    /// Cancels the ongoing album download (issue #14).
    func cancelDownload() {
        downloadTask?.cancel()
    }

    /// Progress of download `id`; ignored once another download took over.
    private func report(_ progress: WebViewModel.DownloadProgress, for id: UUID) {
        guard activeDownloadID == id, !Task.isCancelled else { return }
        host?.nativeXSetDownloadProgress(progress)
    }

    /// Photos and videos (also inside an album ZIP) go to the photo library, like Android saves
    /// them to Downloads; other files, or no access to Photos, open the share sheet.
    ///
    /// Cancellation is checked between the phases: once cancelled, nothing more is extracted,
    /// saved or announced (photos already saved stay saved).
    private func saveOrShare(_ file: URL, album: String?, id: UUID) async {
        let folder = file.deletingLastPathComponent()
        let media = await extractMedia(in: file, folder: folder, album: album, id: id)
        guard !Task.isCancelled else {
            try? FileManager.default.removeItem(at: folder)
            return
        }
        guard !media.isEmpty, await PhotosAccessPrompt.requestAccess() else {
            if !Task.isCancelled { presentShareSheet([file]) }
            return
        }
        let result = await PhotosSaver(library: photoLibrary).save(media, album: album) { [weak self] done, total in
            Task { @MainActor in
                self?.report(.init(phase: .savingToPhotos, done: done, total: total, title: album), for: id)
            }
        }
        try? FileManager.default.removeItem(at: folder)
        guard !Task.isCancelled else { return }
        host?.nativeXToast(Self.message(for: result), long: result.failed > 0)
    }

    /// Extracts the media files of a downloaded file (itself, or the photos/videos of a ZIP),
    /// reporting the extraction progress (issue #14). Runs off the main actor so a large
    /// archive does not freeze the UI.
    private func extractMedia(in file: URL, folder: URL, album: String?, id: UUID) async -> [MediaFile] {
        guard ZipExtractor.isZip(file) else {
            return MediaFile(url: file).map { [$0] } ?? []
        }
        let extracted = folder.appendingPathComponent("extracted", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: extracted, withIntermediateDirectories: true)
            // A detached task is not cancelled with its parent: forward the cancellation.
            let extraction = Task.detached { [weak self] in
                try ZipExtractor.extract(file, into: extracted) { done, total in
                    Task { @MainActor in
                        self?.report(.init(phase: .extracting, done: done, total: total, title: album), for: id)
                    }
                }
            }
            let files = try await withTaskCancellationHandler {
                try await extraction.value
            } onCancel: {
                extraction.cancel()
            }
            return files.compactMap(MediaFile.init(url:))
        } catch {
            Log.nativex.error("ZIP extraction failed: \(String(describing: error), privacy: .public)")
            return []
        }
    }

    static func message(for result: PhotosSaver.Result) -> String {
        if result.failed > 0 {
            return String(localized: "\(result.failed) files could not be saved to Photos")
        }
        if result.saved == 0 {
            return String(localized: "Already in Photos")
        }
        if result.alreadyInPhotos > 0 {
            return String(localized: "Saved to Photos (\(result.saved)), already there: \(result.alreadyInPhotos)")
        }
        return String(localized: "Saved to Photos (\(result.saved))")
    }
}
