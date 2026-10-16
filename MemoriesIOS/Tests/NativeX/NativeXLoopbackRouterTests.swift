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
        router = NativeXLoopbackRouter(share: share, photos: NativeXPhotoService(library: PhotoLibrary()))
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

    func testShareURLPresentsTheDecodedLink() async throws {
        let link = "https://cloud.example.com/s/abc?x=1"
        let once = try XCTUnwrap(link.addingPercentEncoding(withAllowedCharacters: .alphanumerics))
        let twice = try XCTUnwrap(once.addingPercentEncoding(withAllowedCharacters: .alphanumerics))
        let response = await get("/api/share/url/" + twice)
        XCTAssertEqual(response.status, 200)
        XCTAssertEqual(presented.count, 1)
        XCTAssertEqual(presented.first?.first as? URL, URL(string: link))
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
