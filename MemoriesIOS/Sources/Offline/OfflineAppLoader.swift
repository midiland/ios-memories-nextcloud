import Foundation
import WebKit

/// Startup of the locally served app (equivalent of `AppStartupCoordinator.kt`):
/// - snapshot already present → shown immediately, update checked in the background;
/// - otherwise → snapshot downloaded (with progress), then shown;
/// - server without a signed manifest, or failure → `nil`: the caller falls back to remote loading.
@MainActor
final class OfflineAppLoader {
    private let credentials: Credentials
    private let server: LocalHTTPServer
    private let media: LocalMediaProvider?
    private let store = SnapshotStore()
    private(set) var current: Snapshot?

    init(credentials: Credentials, server: LocalHTTPServer, media: LocalMediaProvider? = nil) {
        self.credentials = credentials
        self.server = server
        self.media = media
    }

    /// URL of the local entry page: the app route directly (loading `/` would trigger
    /// a frontend redirect, and thus a second full load).
    var entryURL: URL {
        URL(string: server.origin.absoluteString + credentials.server.appPath + "/")!
    }

    /// Frontend device setup page (`/nxsetup`), opened instead of the entry page on first launch.
    var setupURL: URL {
        entryURL.appendingPathComponent("nxsetup")
    }

    /// Whether `url` points to the local server (loopback host).
    func isLocal(_ url: URL) -> Bool {
        url.host == LocalHTTPServer.host || url.host == "localhost"
    }

    /// Real server page for a proxied local path (e.g. a link to another Nextcloud app),
    /// to open in Safari; `nil` for the app's own pages.
    func serverPage(for url: URL) -> URL? {
        server.router.browserURL(forPath: url.path, query: url.query)
    }

    /// Prepares the local server and a snapshot. Returns the URL to load, or `nil` for the remote fallback.
    /// Throws `AppError.notAuthenticated` / `.serverUnreachable` when no snapshot can help.
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

        // First launch for this server: blocking download.
        guard let manifest = try await fetchVerifiedManifest() else { return nil }
        let snapshot: Snapshot
        do {
            snapshot = try await AssetSyncer(credentials: credentials).sync(manifest, progress: progress)
        } catch {
            Log.offline.error("Snapshot download failed: \(String(describing: error), privacy: .public)")
            return nil
        }
        activate(snapshot)
        return entryURL
    }

    /// Checks the credentials and the web files version. If the server version changed,
    /// downloads the new snapshot and activates it. Returns `true` if the page must be reloaded.
    /// Offline: no error (we keep running on the cached snapshot).
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
        let snapshot: Snapshot
        do {
            snapshot = try await AssetSyncer(credentials: credentials).sync(manifest, progress: { _, _ in })
        } catch {
            Log.offline.error("Snapshot update failed: \(String(describing: error), privacy: .public)")
            return false
        }
        activate(snapshot)
        return true
    }

    /// Restarts listening if iOS closed the socket in the background. `true` if the port changed.
    func ensureServerRunning() async -> Bool {
        let before = server.port
        guard let after = try? await server.ensureStarted() else { return false }
        return before != 0 && after != before
    }

    // MARK: - Private

    /// Authenticated `describe?manifest=1`. `nil` if the server provides no valid manifest.
    private func fetchVerifiedManifest() async throws -> AssetManifest? {
        let (describe, raw) = try await NextcloudClient().describeRaw(credentials.server, credentials: credentials, manifest: true)
        guard describe.uid != nil else { throw AppError.notAuthenticated }
        guard let manifest = try? AssetManifest(raw: raw) else {
            Log.offline.notice("No asset manifest: falling back to remote loading")
            return nil
        }
        guard ManifestVerifier.verify(manifest) else {
            Log.offline.error("Invalid manifest signature: falling back to remote loading")
            return nil
        }
        return manifest
    }

    private func activate(_ snapshot: Snapshot) {
        current = snapshot
        server.router.config = LocalAppConfig(
            credentials: credentials,
            snapshot: snapshot,
            user: snapshot.manifest.describe.uid ?? credentials.loginName,
            media: media
        )
    }

    /// HttpOnly `local-auth` cookie: without it the local server responds 403 (other apps on the device).
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
