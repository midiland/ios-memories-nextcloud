import XCTest
@testable import Memories

/// Routing of the local server, without the network (the proxied case is not covered).
final class LocalRouterTests: XCTestCase {
    private let secret = "s3cret"
    private let host = "127.0.0.1:62079"
    private var directory: URL!
    private var router: LocalRouter!

    override func setUpWithError() throws {
        directory = try Fixtures.temporaryDirectory()
        let manifest = try AssetManifest(raw: Fixtures.describe())
        let store = SnapshotStore()
        try store.prepareEmptyDirectory(directory)
        try store.markReady(directory, manifest: manifest)
        try Data("main()".utf8).write(to: directory.appendingPathComponent("js/memories-main.js"))
        try Data("@import '../../dist/icons.css';".utf8).write(to: directory.appendingPathComponent("css/00_server.css"))

        router = LocalRouter(secret: secret)
        router.port = 62079
        router.config = LocalAppConfig(
            credentials: Fixtures.credentials,
            snapshot: Snapshot(directory: directory, manifest: manifest),
            user: "alice"
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Request carrying the access cookie and the loopback `Host`.
    private func get(_ target: String, headers: [String: String] = [:]) async -> HTTPResponse {
        let all = headers.merging(["Host": host, "Cookie": "local-auth=\(secret)"]) { own, _ in own }
        return await router.handle(Fixtures.request(target, headers: all))
    }

    // MARK: - Access control

    func testRejectsMissingOrWrongCookie() async {
        let noCookie = await router.handle(Fixtures.request("/", headers: ["Host": host]))
        XCTAssertEqual(noCookie.status, 403)
        let wrong = await get("/", headers: ["Cookie": "local-auth=nope"])
        XCTAssertEqual(wrong.status, 403)
    }

    func testRejectsForeignHost() async {
        let response = await get("/", headers: ["Host": "evil.example.org:62079"])
        XCTAssertEqual(response.status, 403)
        let localhost = await get("/nextcloud/", headers: ["Host": "localhost:62079", "Accept": "text/html"])
        XCTAssertEqual(localhost.status, 200)
    }

    func testRefusesCrossSiteMutations() async {
        let crossSiteGet = await get("/api/days", headers: ["Sec-Fetch-Site": "cross-site"])
        XCTAssertEqual(crossSiteGet.status, 404) // a GET is not a mutation: routed (not 403)
        let foreignPost = Fixtures.request("/x", method: "POST", headers: [
            "Host": host, "Cookie": "local-auth=\(secret)", "Origin": "https://evil.example.org",
        ])
        let refused = await router.handle(foreignPost)
        XCTAssertEqual(refused.status, 403)
        let foreignSite = Fixtures.request("/x", method: "DELETE", headers: [
            "Host": host, "Cookie": "local-auth=\(secret)", "Sec-Fetch-Site": "cross-site",
        ])
        let foreignSiteResponse = await router.handle(foreignSite)
        XCTAssertEqual(foreignSiteResponse.status, 403)
    }

    func testPreflightRefusesUnauthorizedHeadsBeforeTheBody() throws {
        let anonymous = try XCTUnwrap(HTTPRequestHead("POST /x HTTP/1.1\r\nHost: \(host)\r\nContent-Length: 500000000"))
        XCTAssertEqual(router.preflight(anonymous)?.status, 403)
        let wrongHost = try XCTUnwrap(HTTPRequestHead("GET / HTTP/1.1\r\nHost: evil.example.org:62079\r\nCookie: local-auth=\(secret)"))
        XCTAssertEqual(router.preflight(wrongHost)?.status, 403)
        let allowed = try XCTUnwrap(HTTPRequestHead("PUT /x HTTP/1.1\r\nHost: \(host)\r\nCookie: local-auth=\(secret)"))
        XCTAssertNil(router.preflight(allowed))
    }

    // MARK: - Local routes

    func testBridgeRoutesAreNotServed() async {
        for target in ["/api/days", "/image/preview/1", "/video/full/1"] {
            let response = await get(target)
            XCTAssertEqual(response.status, 404, target)
        }
    }

    func testServesSnapshotScripts() async {
        let local = await get("/local/assets/js/memories-main.js")
        XCTAssertEqual(local.text, "main()")
        let webpackChunk = await get("/nextcloud/apps/memories/js/memories-main.js")
        XCTAssertEqual(webpackChunk.text, "main()")
        let indexPhp = await get("/nextcloud/index.php/apps/memories/js/memories-main.js")
        XCTAssertEqual(indexPhp.text, "main()")
    }

    func testServesRewrittenStylesheets() async {
        let response = await get("/local/assets/css/00_server.css")
        XCTAssertEqual(response.text, "@import '/nextcloud/dist/icons.css';")
        let unknown = await get("/local/assets/css/99_unknown.css")
        XCTAssertEqual(unknown.status, 404)
    }

    func testOtherLocalPathsStayLocal() async {
        let response = await get("/local/whatever")
        XCTAssertEqual(response.status, 404)
        let favicon = await get("/favicon.ico")
        XCTAssertEqual(favicon.status, 404)
    }

    func testEntryAndAppRoutesServeTheShell() async {
        for target in ["/", "/nextcloud", "/nextcloud/", "/nextcloud/index.php/apps/memories/thisday"] {
            let response = await get(target, headers: ["Accept": "text/html"])
            XCTAssertEqual(response.status, 200, target)
            XCTAssertEqual(response.header("Cache-Control"), "no-store", target)
            XCTAssertTrue(response.header("Content-Security-Policy")?.contains("'nonce-") == true, target)
            XCTAssertTrue(response.text?.contains(#"data-user="alice""#) == true, target)
        }
    }

    // MARK: - oc_config.mod_rewrite_working (issue #7)

    /// The shell must expose `mod_rewrite_working = false` when the upstream server's
    /// canonical `baseUrl` contains `index.php` (the fixture's default).
    func testShellSetsModRewriteWorkingFalseWhenServerUsesIndexPHP() async {
        let response = await get("/", headers: ["Accept": "text/html"])
        XCTAssertEqual(response.status, 200)
        XCTAssertTrue(response.text?.contains("window.oc_config.mod_rewrite_working = false;") == true)
    }

    /// When the upstream server serves pretty URLs (no `index.php` in its `baseUrl`), the shell
    /// must expose `mod_rewrite_working = true` so `generateUrl()` omits `index.php` in public
    /// share links — even though the stored server URL carries `index.php` (the default added to
    /// the address the user types). Otherwise the public page shows no photos.
    func testShellSetsModRewriteWorkingTrueWhenServerUsesPrettyURLs() async throws {
        let manifest = try AssetManifest(raw: Fixtures.describe(baseUrl: "https://cloud.example.com/nextcloud/apps/memories/"))
        router.config = LocalAppConfig(
            credentials: Fixtures.credentials, // stored URL contains `index.php`
            snapshot: Snapshot(directory: directory, manifest: manifest),
            user: "alice"
        )
        XCTAssertTrue(Fixtures.credentials.server.memoriesURL.absoluteString.contains("index.php"))
        let response = await get("/", headers: ["Accept": "text/html"])
        XCTAssertEqual(response.status, 200)
        XCTAssertTrue(response.text?.contains("window.oc_config.mod_rewrite_working = true;") == true)
    }

    /// The stored URL is ignored: a pretty stored URL does not hide a server that needs `index.php`.
    func testShellIgnoresStoredServerURLStyle() async throws {
        let pretty = ServerURL(memoriesBaseURL: "https://cloud.example.com/nextcloud/apps/memories/")!
        router.config = LocalAppConfig(
            credentials: Credentials(server: pretty, loginName: "alice", appPassword: "secret"),
            snapshot: router.config!.snapshot, // `baseUrl` with `index.php`
            user: "alice"
        )
        let response = await get("/", headers: ["Accept": "text/html"])
        XCTAssertTrue(response.text?.contains("window.oc_config.mod_rewrite_working = false;") == true)
    }

    func testOtherDocumentNavigationsAreNotRenderedLocally() async {
        let response = await get("/nextcloud/index.php/apps/files/", headers: ["Sec-Fetch-Dest": "document"])
        XCTAssertEqual(response.status, 404)
    }

    func testUnconfiguredRouterAnswers503() async {
        router.config = nil
        let response = await get("/nextcloud/index.php/apps/memories/", headers: ["Accept": "text/html"])
        XCTAssertEqual(response.status, 503)
    }

    // MARK: - Device photos

    func testServesDevicePhotosAsJPEG() async {
        router.config?.media = FakeMedia()
        let preview = await get("/image/preview/42?c=1&x=256&y=128")
        XCTAssertEqual(preview.status, 200)
        XCTAssertEqual(preview.header("Content-Type"), "image/jpeg")
        XCTAssertEqual(preview.text, "preview 42 256x128")

        let full = await get("/image/full/abc?size=1024")
        XCTAssertEqual(full.text, "full abc 1024")
        let original = await get("/image/full/abc")
        XCTAssertEqual(original.text, "full abc -")
    }

    func testUnknownOrUnavailableDevicePhotos() async {
        let withoutMedia = await get("/image/preview/42")
        XCTAssertEqual(withoutMedia.status, 404)

        router.config?.media = FakeMedia()
        for target in ["/image/preview/unknown", "/image/preview/notanumber", "/image/other/1", "/image/preview/1/2"] {
            let response = await get(target)
            XCTAssertEqual(response.status, 404, target)
        }
    }

    // MARK: - Browser URL

    func testBrowserURLForProxiedPaths() {
        XCTAssertEqual(
            router.browserURL(forPath: "/nextcloud/index.php/apps/files/", query: "dir=/")?.absoluteString,
            "https://cloud.example.com/nextcloud/index.php/apps/files/?dir=/"
        )
    }

    func testNoBrowserURLForLocalPaths() {
        for path in ["/", "/nextcloud", "/nextcloud/", "/favicon.ico", "/local/x", "/api/days",
                     "/nextcloud/index.php/apps/memories/albums", "/nextcloud/apps/memories/js/a.js"] {
            XCTAssertNil(router.browserURL(forPath: path, query: nil), path)
        }
    }
}

/// Returns a description of the request instead of an image; fileid 1 / auid "unknown" are missing.
private struct FakeMedia: LocalMediaProvider {
    func preview(fileId: Int64, width: Int?, height: Int?) async -> Data? {
        fileId == 1 ? nil : Data("preview \(fileId) \(width ?? 0)x\(height ?? 0)".utf8)
    }

    func full(auid: String, longEdge: Int?) async -> Data? {
        auid == "unknown" ? nil : Data("full \(auid) \(longEdge.map(String.init) ?? "-")".utf8)
    }
}
