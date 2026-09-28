import Foundation
import WebKit

/// Démarrage de l'app servie localement (équivalent de `AppStartupCoordinator.kt`) :
/// - snapshot déjà présent → affichage immédiat, mise à jour vérifiée en arrière-plan ;
/// - sinon → téléchargement du snapshot (avec progression) puis affichage ;
/// - serveur sans manifeste signé, ou échec → `nil` : l'appelant se replie sur le chargement distant.
@MainActor
final class OfflineAppLoader {
    private let credentials: Credentials
    private let server = LocalHTTPServer.shared
    private let store = SnapshotStore()
    private(set) var current: Snapshot?

    init(credentials: Credentials) {
        self.credentials = credentials
    }

    /// URL de la page d'entrée locale : directement la route de l'app (charger `/`
    /// provoquerait une redirection du frontend, donc un second chargement complet).
    var entryURL: URL {
        URL(string: server.origin.absoluteString + credentials.server.webRoot + "/index.php/apps/memories/")!
    }

    /// Prépare le serveur local et un snapshot. Renvoie l'URL à charger, ou `nil` pour le repli distant.
    /// Lève `AppError.notAuthenticated` / `.serverUnreachable` quand aucun snapshot ne peut aider.
    func prepare(into cookieStore: WKHTTPCookieStore, progress: @escaping AssetSyncer.Progress) async throws -> URL? {
        do {
            try await server.ensureStarted()
        } catch {
            return nil
        }
        await installAccessCookie(into: cookieStore)

        if let snapshot = store.latest(for: credentials.server) {
            activate(snapshot)
            return entryURL
        }

        // Premier lancement pour ce serveur : téléchargement bloquant.
        guard let manifest = try await fetchVerifiedManifest() else { return nil }
        let snapshot: Snapshot
        do {
            snapshot = try await AssetSyncer(credentials: credentials).sync(manifest, progress: progress)
        } catch {
            Log.offline.error("Téléchargement du snapshot échoué : \(String(describing: error), privacy: .public)")
            return nil
        }
        activate(snapshot)
        return entryURL
    }

    /// Vérifie les identifiants et la version des fichiers web. Si le serveur a changé de version,
    /// télécharge le nouveau snapshot et l'active. Renvoie `true` si la page doit être rechargée.
    /// Hors ligne : aucune erreur (on continue avec le snapshot en cache).
    func refreshInBackground() async throws -> Bool {
        let manifest: AssetManifest?
        do {
            manifest = try await fetchVerifiedManifest()
        } catch AppError.notAuthenticated {
            throw AppError.notAuthenticated
        } catch {
            return false
        }
        guard let manifest, manifest.key != current?.key else { return false }
        guard let snapshot = try? await AssetSyncer(credentials: credentials).sync(manifest, progress: { _, _ in }) else {
            return false
        }
        activate(snapshot)
        return true
    }

    /// Relance l'écoute si iOS a fermé le socket en arrière-plan. `true` si le port a changé.
    func ensureServerRunning() async -> Bool {
        let before = server.port
        guard let after = try? await server.ensureStarted() else { return false }
        return before != 0 && after != before
    }

    // MARK: - Privé

    /// `describe?manifest=1` authentifié. `nil` si le serveur ne fournit pas de manifeste valide.
    private func fetchVerifiedManifest() async throws -> AssetManifest? {
        let (describe, raw) = try await NextcloudClient().describeRaw(credentials.server, credentials: credentials, manifest: true)
        guard describe.uid != nil else { throw AppError.notAuthenticated }
        guard let manifest = try? AssetManifest(raw: raw) else {
            Log.offline.notice("Pas de manifeste d'assets : repli sur le chargement distant")
            return nil
        }
        guard ManifestVerifier.verify(manifest) else {
            Log.offline.error("Signature du manifeste invalide : repli sur le chargement distant")
            return nil
        }
        return manifest
    }

    private func activate(_ snapshot: Snapshot) {
        current = snapshot
        server.router.config = LocalAppConfig(
            credentials: credentials,
            snapshot: snapshot,
            user: snapshot.manifest.describe.uid ?? credentials.loginName
        )
    }

    /// Cookie HttpOnly `local-auth` : sans lui le serveur local répond 403 (autres apps de l'appareil).
    private func installAccessCookie(into cookieStore: WKHTTPCookieStore) async {
        let properties: [HTTPCookiePropertyKey: Any] = [
            .name: "local-auth",
            .value: server.secret,
            .domain: LocalHTTPServer.host,
            .path: "/",
            HTTPCookiePropertyKey("HttpOnly"): "TRUE",
        ]
        if let cookie = HTTPCookie(properties: properties) {
            await cookieStore.setCookie(cookie)
        }
    }
}
