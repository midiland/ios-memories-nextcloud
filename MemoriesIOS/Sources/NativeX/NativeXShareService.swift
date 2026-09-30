import Foundation

/// Downloads and sharing requested by the web UI
/// (`downloadFromUrl`, `setShareBlobs` + `/api/share/blobs`, `/api/share/url`).
///
/// Android saves to "Downloads" with a notification; on iOS we go through
/// the share sheet (which offers "Save Image" / "Save to Files").
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
    /// Shows the share sheet for files or links.
    private let presentShareSheet: @MainActor ([Any]) -> Void
    private var stagedBlobs: [Blob] = []

    init(downloader: AuthenticatedDownloader, presentShareSheet: @escaping @MainActor ([Any]) -> Void) {
        self.downloader = downloader
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

    /// `nativex.downloadFromUrl(url, filename, title)`: background download,
    /// then share sheet; toast on failure.
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
                presentShareSheet([file])
            } catch {
                self.host?.nativeXToast(String(localized: "Download failed: \(error.localizedDescription)"), long: true)
            }
        }
    }
}
