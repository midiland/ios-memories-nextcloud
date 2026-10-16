import Foundation

/// Downloads a file from the Nextcloud server into a temporary folder.
///
/// Credentials are sent **only** if the URL points to the account's server
/// (never to a third-party host). URLs on the app's local server (what the frontend passes:
/// it builds them on the page origin) carry the `local-auth` cookie, and the local server relays
/// them to Nextcloud with the credentials.
struct AuthenticatedDownloader {
    let credentials: Credentials
    /// Current port and secret of the local server, `nil` when it is not running.
    var localServer: @MainActor () -> LocalServerAccess? = { nil }

    /// Downloads `url` and returns the local file, named after `Content-Disposition`
    /// (or `preferredName` if provided).
    func download(_ url: URL, preferredName: String? = nil) async throws -> URL {
        let request = URLRequest(url: url, authorizedFor: credentials, localServer: await localServer())

        let (tempFile, response): (URL, URLResponse)
        do {
            (tempFile, response) = try await URLSession.shared.download(for: request)
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
