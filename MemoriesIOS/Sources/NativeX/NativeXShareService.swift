import Foundation

/// Téléchargement et partage demandés par l'UI web
/// (`downloadFromUrl`, `setShareBlobs` + `/api/share/blobs`, `/api/share/url`).
///
/// Android enregistre dans « Téléchargements » avec une notification ; sur iOS on passe
/// par la feuille de partage (qui propose « Enregistrer l'image » / « Enregistrer dans Fichiers »).
@MainActor
final class NativeXShareService {
    /// Objet posé par `setShareBlobs` (JSON `[{ auid, href }]`).
    private struct Blob: Decodable {
        let auid: String?
        let href: String
    }

    weak var host: NativeXHost?
    private var stagedBlobs: [Blob] = []

    /// `nativex.setShareBlobs(json)` : mémorise les fichiers du prochain `/api/share/blobs`.
    func stageBlobs(_ json: String?) {
        guard let data = json?.data(using: .utf8),
              let blobs = try? JSONDecoder().decode([Blob].self, from: data)
        else { stagedBlobs = []; return }
        stagedBlobs = blobs
    }

    /// `/api/share/blobs` : télécharge les fichiers préparés puis ouvre le partage.
    /// Ne rend la main qu'une fois les téléchargements terminés (contrat du frontend).
    func shareStagedBlobs() async -> Bool {
        let blobs = stagedBlobs
        stagedBlobs = []
        guard let host, !blobs.isEmpty else { return false }

        let downloader = AuthenticatedDownloader(credentials: host.credentials)
        var files: [URL] = []
        for blob in blobs {
            guard let url = URL(string: blob.href) else { continue }
            if let file = try? await downloader.download(url) { files.append(file) }
        }
        guard !files.isEmpty else { return false }
        SharePresenter.present(files)
        return true
    }

    /// `/api/share/url/…` : partage le lien tel quel, sans le télécharger.
    func shareLink(_ url: URL) {
        SharePresenter.present([url])
    }

    /// `nativex.downloadFromUrl(url, filename, title)` : téléchargement en arrière-plan,
    /// puis feuille de partage ; toast en cas d'échec.
    func download(urlString: String?, filename: String?, title: String?) {
        guard let urlString, let url = URL(string: urlString), let host else { return }
        let label = (title?.isEmpty == false ? title : nil) ?? "le fichier"
        host.nativeXToast("Téléchargement de \(label)…", long: false)

        let downloader = AuthenticatedDownloader(credentials: host.credentials)
        let name = filename?.isEmpty == false ? filename : nil
        Task {
            do {
                let file = try await downloader.download(url, preferredName: name)
                SharePresenter.present([file])
            } catch {
                self.host?.nativeXToast("Échec du téléchargement : \(error.localizedDescription)", long: true)
            }
        }
    }
}
