import Foundation
import WebKit

/// Startup of the locally served app (equivalent of `AppStartupCoordinator.kt`):
/// - snapshot already present → shown immediately, update checked in the background;
/// - otherwise → snapshot downloaded (with progress), then shown.
///
/// The server is untrusted for code loading: the web files only ever come from a snapshot
/// whose manifest parses and verifies. There is no fallback to loading them from the server.
@MainActor
final class OfflineAppLoader {
    /// Outcome of the background update check.
    enum UpdateCheck: Equatable {
        /// Same web files as the running snapshot, or the server could not be reached.
        case upToDate
        /// A new verified snapshot is active: the page must be reloaded.
        case updated
        /// The server offers web files that do not verify: the app keeps the previous snapshot.
        case unverifiable
    }

    private let credentials: Credentials
    private let server: LocalHTTPServer
    private let media: LocalMediaProvider?
    private let store = SnapshotStore()
    private let pins = ManifestPinStore()
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

    /// Whether `url` points to the local server: loopback host AND its port (another loopback
    /// server must not receive the `local-auth` cookie).
    func isLocal(_ url: URL) -> Bool {
        LocalOrigin.matches(url, localPort: server.port)
    }

    /// Real server page for a proxied local path (e.g. a link to another Nextcloud app),
    /// to open in Safari; `nil` for the app's own pages.
    func serverPage(for url: URL) -> URL? {
        server.router.browserURL(forPath: url.path, query: url.query)
    }

    /// Prepares the local server and a snapshot, and returns the URL to load. Throws `AppError`
    /// when the local server cannot start or the web files cannot be verified or downloaded.
    func prepare(into cookieStore: WKHTTPCookieStore, progress: @escaping AssetSyncer.Progress) async throws -> URL {
        do {
            try await server.ensureStarted()
        } catch {
            Log.localServer.error("Start failed: \(String(describing: error), privacy: .public)")
            throw AppError.localServerUnavailable
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
    /// downloads the new snapshot and activates it. The app keeps running on the cached
    /// snapshot in every other case; only revoked credentials are thrown.
    func refreshInBackground() async throws -> UpdateCheck {
        let manifest: AssetManifest
        do {
            manifest = try await fetchVerifiedManifest()
        } catch AppError.notAuthenticated {
            throw AppError.notAuthenticated
        } catch {
            return Self.updateCheck(after: error)
        }
        guard manifest.key != current?.key else { return .upToDate }
        let snapshot: Snapshot
        do {
            snapshot = try await AssetSyncer(credentials: credentials).sync(manifest, progress: { _, _ in })
        } catch {
            Log.offline.error("Snapshot update failed: \(String(describing: error), privacy: .public)")
            return Self.updateCheck(after: error)
        }
        activate(snapshot)
        return .updated
    }

    /// A failed update check is only worth telling the user when the server's web files do not
    /// verify: being offline or a transient network error just means trying again next time.
    static func updateCheck(after error: Error) -> UpdateCheck {
        switch AppError.from(error) {
        case .noSignedManifest, .webFilesCorrupted: return .unverifiable
        default: return .upToDate
        }
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
    /// server provides no manifest that parses and verifies, or an older one than already
    /// accepted for this account (`ManifestPin`): its code is untrusted.
    private func fetchVerifiedManifest() async throws -> AssetManifest {
        let (describe, raw) = try await NextcloudClient().describeRaw(credentials.server, credentials: credentials, manifest: true)
        guard describe.uid != nil else { throw AppError.notAuthenticated }
        guard let manifest = try? AssetManifest(raw: raw), ManifestVerifier.verify(manifest) else {
            Log.offline.error("No valid signed manifest: refusing to load server code")
            throw AppError.noSignedManifest
        }
        let pin = pins.pin(for: credentials)
        guard ManifestPin.allows(manifest, after: pin) else {
            Log.offline.error("Manifest older than the one already accepted: refusing a rollback")
            throw AppError.noSignedManifest
        }
        pins.save(ManifestPin.updated(pin, accepting: manifest), for: credentials)
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
            .sameSitePolicy: HTTPCookieStringPolicy.sameSiteStrict,
        ]
        if let cookie = HTTPCookie(properties: properties) {
            await cookieStore.setCookie(cookie)
        }
    }
}
