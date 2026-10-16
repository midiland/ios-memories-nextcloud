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

    /// Receives the toasts (download started / failed).
    weak var host: NativeXHost?
    private let downloader: AuthenticatedDownloader
    private let photoLibrary: PhotoLibrary
    /// Shows the share sheet for files or links.
    private let presentShareSheet: @MainActor ([Any]) -> Void
    private var stagedBlobs: [Blob] = []

    init(
        downloader: AuthenticatedDownloader,
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
    /// named `title`) or the share sheet; toast with the result.
    func download(urlString: String?, filename: String?, title: String?) {
        guard let urlString, let url = URL(string: urlString), let host else { return }
        if let title, !title.isEmpty {
            host.nativeXToast(String(localized: "Downloading \(title)…"), long: false)
        } else {
            host.nativeXToast(String(localized: "Downloading…"), long: false)
        }

        let name = filename?.isEmpty == false ? filename : nil
        Task {
            do {
                let file = try await downloader.download(url, preferredName: name)
                await saveOrShare(file, album: title)
            } catch {
                self.host?.nativeXToast(String(localized: "Download failed: \(error.localizedDescription)"), long: true)
            }
        }
    }

    /// Photos and videos (also inside an album ZIP) go to the photo library, like Android saves
    /// them to Downloads; other files, or no access to Photos, open the share sheet.
    private func saveOrShare(_ file: URL, album: String?) async {
        let folder = file.deletingLastPathComponent()
        let media = await Task.detached { Self.mediaFiles(in: file, folder: folder) }.value
        guard !media.isEmpty, await PhotosAccessPrompt.requestAccess() else {
            presentShareSheet([file])
            return
        }
        let result = await PhotosSaver(library: photoLibrary).save(media, album: album)
        try? FileManager.default.removeItem(at: folder)
        host?.nativeXToast(Self.message(for: result), long: result.failed > 0)
    }

    /// The downloaded file itself, or the photos and videos of a ZIP (extracted next to it).
    private nonisolated static func mediaFiles(in file: URL, folder: URL) -> [MediaFile] {
        guard ZipExtractor.isZip(file) else { return MediaFile(url: file).map { [$0] } ?? [] }
        let extracted = folder.appendingPathComponent("extracted", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: extracted, withIntermediateDirectories: true)
            return try ZipExtractor.extract(file, into: extracted).compactMap(MediaFile.init(url:))
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
