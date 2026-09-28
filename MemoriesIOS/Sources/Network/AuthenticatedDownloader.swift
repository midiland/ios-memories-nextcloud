import Foundation

/// Télécharge un fichier du serveur Nextcloud vers un dossier temporaire.
///
/// Les identifiants ne sont envoyés **que** si l'URL pointe vers le serveur du compte
/// (jamais vers un hôte tiers).
struct AuthenticatedDownloader {
    let credentials: Credentials

    /// Télécharge `url` et renvoie le fichier local, nommé d'après `Content-Disposition`
    /// (ou `preferredName` s'il est fourni).
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

        // Dossier unique par téléchargement pour garder le vrai nom de fichier.
        let name = [preferredName, response.suggestedFilename, url.lastPathComponent]
            .compactMap { $0 }
            .first { !$0.isEmpty } ?? "fichier"
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("downloads", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appendingPathComponent(name.replacingOccurrences(of: "/", with: "_"))
        try FileManager.default.moveItem(at: tempFile, to: destination)
        return destination
    }
}
