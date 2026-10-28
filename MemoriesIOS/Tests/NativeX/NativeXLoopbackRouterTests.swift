import XCTest
@testable import Memories

@MainActor
final class NativeXLoopbackRouterTests: XCTestCase {
    private var presented: [[Any]] = []
    private var share: NativeXShareService!
    private var router: NativeXLoopbackRouter!

    override func setUp() async throws {
        presented = []
        share = NativeXShareService(
            downloader: AuthenticatedDownloader(credentials: Fixtures.credentials),
            photoLibrary: PhotoLibrary(),
            presentShareSheet: { [unowned self] items in presented.append(items) }
        )
        // No timeline attached (before the first load): no device photos.
        let serverOrigin = Fixtures.credentials.server.origin
        router = NativeXLoopbackRouter(share: share, photos: NativeXPhotoService(library: PhotoLibrary()), serverOrigin: serverOrigin)
    }

    private func get(_ path: String, method: String = "GET") async -> NativeXResponse {
        await router.handle(method: method, url: URL(string: "http://127.0.0.1" + path)!)
    }

    func testNoDevicePhotosWithoutTimeline() async {
        let days = await get("/api/days")
        XCTAssertEqual(days.status, 200)
        XCTAssertEqual(days.body, "[]")
        let day = await get("/api/days/19000")
        XCTAssertEqual(day.body, "[]")
        let info = await get("/api/image/info/42")
        XCTAssertEqual(info.status, 404)
    }

    func testLocalDeleteDeletesNothing() async {
        let response = await get("/api/image/delete/1,2")
        XCTAssertEqual(response.body, #"{"confirms":false,"count":0}"#)
    }

    /// Shares `link` through the route (double-encoded like the frontend) and returns the presented URL.
    private func sharedURL(
        _ link: String, serverOrigin: URL? = nil, webRoot: String = "", prettyURLs: Bool? = nil
    ) async throws -> URL? {
        if serverOrigin != nil || prettyURLs != nil {
            router = NativeXLoopbackRouter(
                share: share, photos: router.photos, serverOrigin: serverOrigin ?? router.serverOrigin,
                webRoot: webRoot, servesPrettyURLs: { prettyURLs }
            )
        }
        let once = try XCTUnwrap(link.addingPercentEncoding(withAllowedCharacters: .alphanumerics))
        let twice = try XCTUnwrap(once.addingPercentEncoding(withAllowedCharacters: .alphanumerics))
        let response = await get("/api/share/url/" + twice)
        XCTAssertEqual(response.status, 200)
        XCTAssertEqual(presented.count, 1)
        return presented.first?.first as? URL
    }

    func testShareURLPresentsTheDecodedLink() async throws {
        let link = "https://cloud.example.com/s/abc?x=1"
        let shared = try await sharedURL(link)
        XCTAssertEqual(shared, URL(string: link))
    }

    func testShareURLMovesLocalLinksToTheServerOrigin() async throws {
        let path = "/nextcloud/index.php/apps/memories/a/abc?x=1#top"
        let expected = URL(string: "https://cloud.example.com" + path)
        for host in ["http://127.0.0.1:62079", "http://127.0.0.1", "http://localhost:62079"] {
            presented = []
            let shared = try await sharedURL(host + path)
            XCTAssertEqual(shared, expected, host)
        }
    }

    func testShareURLUsesTheServerPort() async throws {
        let shared = try await sharedURL(
            "http://127.0.0.1:62079/index.php/s/abc",
            serverOrigin: try XCTUnwrap(URL(string: "http://cloud.example.com:8080"))
        )
        XCTAssertEqual(shared, URL(string: "http://cloud.example.com:8080/index.php/s/abc"))
    }

    /// Issue #7: the page runs under `index.php`, so the frontend builds `/index.php/apps/memories/a/…`
    /// even on a server with pretty URLs, where the public page shows no photos.
    func testShareURLDropsIndexPHPOnServersWithPrettyURLs() async throws {
        let shared = try await sharedURL(
            "http://127.0.0.1:62079/index.php/apps/memories/a/abc", webRoot: "", prettyURLs: true
        )
        XCTAssertEqual(shared, URL(string: "https://cloud.example.com/apps/memories/a/abc"))
    }

    func testShareURLKeepsWebRootWhenDroppingIndexPHP() async throws {
        let shared = try await sharedURL(
            "http://127.0.0.1:62079/nextcloud/index.php/apps/memories/a/abc?x=1", webRoot: "/nextcloud", prettyURLs: true
        )
        XCTAssertEqual(shared, URL(string: "https://cloud.example.com/nextcloud/apps/memories/a/abc?x=1"))
    }

    func testShareURLAddsIndexPHPOnServersWithoutPrettyURLs() async throws {
        let shared = try await sharedURL("http://127.0.0.1:62079/apps/memories/a/abc", prettyURLs: false)
        XCTAssertEqual(shared, URL(string: "https://cloud.example.com/index.php/apps/memories/a/abc"))
    }

    func testShareURLLeavesNonAppPathsAlone() async throws {
        let shared = try await sharedURL("http://127.0.0.1:62079/index.php/s/abc", prettyURLs: true)
        XCTAssertEqual(shared, URL(string: "https://cloud.example.com/index.php/s/abc"))
    }

    func testShareURLKeepsTheLinkStyleWhileTheServerStyleIsUnknown() async throws {
        let shared = try await sharedURL("http://127.0.0.1:62079/index.php/apps/memories/a/abc")
        XCTAssertEqual(shared, URL(string: "https://cloud.example.com/index.php/apps/memories/a/abc"))
    }

    func testShareURLKeepsOtherHostsUnchanged() async throws {
        for link in ["https://other.example.com/s/abc?x=1", "http://cloud.example.com/s/abc"] {
            presented = []
            let shared = try await sharedURL(link)
            XCTAssertEqual(shared, URL(string: link), link)
        }
    }

    func testShareBlobsWithoutStagedFilesFails() async {
        share.stageBlobs("not json")
        let response = await get("/api/share/blobs")
        XCTAssertEqual(response.status, 500)
        XCTAssertTrue(presented.isEmpty)
    }

    func testStubRoutes() async {
        // Opt-out only: opting in would show the iOS permission prompt.
        let allowMedia = await get("/api/config/allow_media/0")
        XCTAssertEqual(allowMedia.body, #""done""#)
        let progress = await get("/api/assets/progress")
        XCTAssertTrue(progress.body.contains(#""status":"ready""#))
    }

    func testUnknownRoutesAndMethods() async {
        let unknown = await get("/api/upload/local")
        XCTAssertEqual(unknown.status, 404)
        let post = await get("/api/days", method: "POST")
        XCTAssertEqual(post.status, 500)
    }

    func testResponseDictionaryFormat() {
        let dictionary = NativeXResponse.json("[1]").dictionary
        XCTAssertEqual(dictionary["status"] as? Int, 200)
        XCTAssertEqual(dictionary["contentType"] as? String, "application/json")
        XCTAssertEqual(dictionary["body"] as? String, "[1]")
    }
}
