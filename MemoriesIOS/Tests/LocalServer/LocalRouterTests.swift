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

    func testOtherDocumentNavigationsAreNotRenderedLocally() async {
        let response = await get("/nextcloud/index.php/apps/files/", headers: ["Sec-Fetch-Dest": "document"])
        XCTAssertEqual(response.status, 404)
    }

    func testUnconfiguredRouterAnswers503() async {
        router.config = nil
        let response = await get("/nextcloud/index.php/apps/memories/", headers: ["Accept": "text/html"])
        XCTAssertEqual(response.status, 503)
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
