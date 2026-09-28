import Foundation

/// Downloads a file from the Nextcloud server into a temporary folder.
///
/// Credentials are sent **only** if the URL points to the account's server
/// (never to a third-party host).
struct AuthenticatedDownloader {
    let credentials: Credentials

    /// Downloads `url` and returns the local file, named after `Content-Disposition`
    /// (or `preferredName` if provided).
    func download(_ url: URL, preferredName: String? = nil) async throws -> URL {
        var request = URLRequest(url: url)
        request.setValue(AppConstants.userAgentSuffix, forHTTPHeaderField: "User-Agent")
        if url.host == credentials.server.host {
            request.setValue(credentials.basicAuthHeader, forHTTPHeaderField: "Authorization")
            request.setValue("true", forHTTPHeaderField: "OCS-APIREQUEST")
        }

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
