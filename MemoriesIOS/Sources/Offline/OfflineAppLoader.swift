import Foundation
import WebKit

/// Startup of the locally served app (equivalent of `AppStartupCoordinator.kt`):
/// - snapshot already present → shown immediately, update checked in the background;
/// - otherwise → snapshot downloaded (with progress), then shown;
/// - local server failure → `nil`: the caller falls back to remote loading.
///
/// The server is untrusted for code loading: without a manifest that parses and
/// verifies, `AppError.noSignedManifest` is thrown instead of a remote fallback.
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

    /// Prepares the local server and a snapshot. Returns the URL to load, or `nil` if the
    /// local server cannot start (remote fallback). Throws `AppError` when the web files
    /// cannot be verified or downloaded: the server code must not be loaded instead.
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
        let manifest = try await fetchVerifiedManifest()
        let snapshot: Snapshot
        do {
            snapshot = try await AssetSyncer(credentials: credentials).sync(manifest, progress: progress)
        } catch {
            Log.offline.error("Snapshot download failed: \(String(describing: error), privacy: .public)")
            throw AppError.from(error)
        }
        activate(snapshot)
        return entryURL
    }

    /// Checks the credentials and the web files version. If the server version changed,
    /// downloads the new snapshot and activates it. Returns `true` if the page must be reloaded.
    /// Offline, unverified manifest or failed download: no error (we keep running on the cached snapshot).
    func refreshInBackground() async throws -> Bool {
        let manifest: AssetManifest
        do {
            manifest = try await fetchVerifiedManifest()
        } catch AppError.notAuthenticated {
            throw AppError.notAuthenticated
        } catch {
            return false
        }
        guard manifest.key != current?.key else { return false }
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

    /// Stops listening in the background: iOS would reclaim the socket of the suspended app.
    func suspendServer() {
        server.suspend()
    }

    /// Listens again on return. Returns the port, `nil` if the server cannot start.
    func ensureServerRunning() async -> UInt16? {
        do {
            return try await server.ensureStarted()
        } catch {
            Log.localServer.error("Restart failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    // MARK: - Private

    /// Authenticated `describe?manifest=1`. Throws `AppError.noSignedManifest` when the
    /// server provides no manifest that parses and verifies: its code is untrusted.
    private func fetchVerifiedManifest() async throws -> AssetManifest {
        let (describe, raw) = try await NextcloudClient().describeRaw(credentials.server, credentials: credentials, manifest: true)
        guard describe.uid != nil else { throw AppError.notAuthenticated }
        guard let manifest = try? AssetManifest(raw: raw), ManifestVerifier.verify(manifest) else {
            Log.offline.error("No valid signed manifest: refusing to load server code")
            throw AppError.noSignedManifest
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
