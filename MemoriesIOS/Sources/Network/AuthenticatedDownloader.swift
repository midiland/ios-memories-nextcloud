import Foundation

/// Downloads a file from the Nextcloud server into a temporary folder.
///
/// Only http(s) URLs on the account's server or the local server are downloaded
/// (`DownloadURLPolicy`). Credentials are sent **only** if the URL points to the account's server
/// (never to a third-party host). URLs on the app's local server (what the frontend passes:
/// it builds them on the page origin) carry the `local-auth` cookie, and the local server relays
/// them to Nextcloud with the credentials.
/// Downloads a URL to a local file (the network implementation, or a stub in tests).
protocol FileDownloading {
    func download(
        _ url: URL, preferredName: String?, progress: (@Sendable (Int64, Int64) -> Void)?
    ) async throws -> URL
}

extension FileDownloading {
    func download(_ url: URL) async throws -> URL {
        try await download(url, preferredName: nil, progress: nil)
    }

    func download(_ url: URL, preferredName: String?, progress: (@Sendable (Int64, Int64) -> Void)? = nil) async throws -> URL {
        try await download(url, preferredName: preferredName, progress: progress)
    }
}

struct AuthenticatedDownloader: FileDownloading {
    let credentials: Credentials
    /// Current port and secret of the local server, `nil` when it is not running.
    var localServer: @MainActor () -> LocalServerAccess? = { nil }

    /// Downloads `url` and returns the local file, named after `Content-Disposition`
    /// (or `preferredName` if provided). `progress(done, total)` is called with the bytes
    /// downloaded so far and the expected total (0 when the server does not send a length),
    /// so the UI can show a progress bar (issue #14).
    func download(
        _ url: URL,
        preferredName: String? = nil,
        progress: (@Sendable (Int64, Int64) -> Void)? = nil
    ) async throws -> URL {
        let access = await localServer()
        guard DownloadURLPolicy.isAllowed(url, serverOrigin: credentials.server.origin, local: access) else {
            throw AppError.invalidURL
        }
        let request = URLRequest(url: url, authorizedFor: credentials, localServer: access)

        // A dedicated session with a delegate so we can track the download progress.
        let delegate = DownloadDelegate(progress: progress)
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        let (tempFile, response): (URL, URLResponse)
        do {
            (tempFile, response) = try await session.download(for: request)
        } catch {
            throw AppError.from(error)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw AppError.unexpectedStatus(status) }

        // One folder per download, to keep the real file name.
        let name = [preferredName, response.suggestedFilename, url.lastPathComponent]
            .compactMap { $0 }
            .first { !$0.isEmpty } ?? String(localized: "file", comment: "Fallback name of a downloaded file")
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("downloads", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appendingPathComponent(name.replacingOccurrences(of: "/", with: "_"))
        try FileManager.default.moveItem(at: tempFile, to: destination)
        return destination
    }
}

/// Tracks the progress of a `URLSession` download task (issue #14).
private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let progress: (@Sendable (Int64, Int64) -> Void)?

    init(progress: (@Sendable (Int64, Int64) -> Void)?) {
        self.progress = progress
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        progress?(totalBytesWritten, totalBytesExpectedToWrite)
    }

    // Required by the protocol but not called: the async `download(for:)` handles
    // the completion itself (the file is at the temporary location it returns).
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {}
}
