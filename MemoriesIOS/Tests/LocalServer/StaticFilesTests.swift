import XCTest
@testable import Memories

final class StaticFilesTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = try Fixtures.temporaryDirectory()
        try Data("console.log(1)".utf8).write(to: directory.appendingPathComponent("app.js"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testServesFileWithETag() throws {
        let response = StaticFiles.file(Fixtures.request("/local/assets/js/app.js"), in: directory)
        XCTAssertEqual(response.status, 200)
        XCTAssertEqual(response.text, "console.log(1)")
        XCTAssertEqual(response.header("Content-Type"), "text/javascript; charset=utf-8")
        XCTAssertNotNil(response.header("ETag"))
    }

    func testMatchingETagReturnsNotModified() throws {
        let etag = try XCTUnwrap(StaticFiles.file(Fixtures.request("/x/app.js"), in: directory).header("ETag"))
        let response = StaticFiles.file(Fixtures.request("/x/app.js", headers: ["If-None-Match": "\"other\", \(etag)"]), in: directory)
        XCTAssertEqual(response.status, 304)
    }

    func testTransformIsAppliedAndVersionedInETag() throws {
        let plain = try XCTUnwrap(StaticFiles.file(Fixtures.request("/x/app.js"), in: directory).header("ETag"))
        let response = StaticFiles.file(
            Fixtures.request("/x/app.js"), in: directory, transform: (version: "r9", apply: { _ in Data("rewritten".utf8) })
        )
        XCTAssertEqual(response.text, "rewritten")
        XCTAssertNotEqual(response.header("ETag"), plain)
        XCTAssertTrue(response.header("ETag")?.hasSuffix("-r9\"") == true)
    }

    func testRejectsMissingFilesTraversalAndOtherMethods() {
        XCTAssertEqual(StaticFiles.file(Fixtures.request("/x/missing.js"), in: directory).status, 404)
        XCTAssertEqual(StaticFiles.file(Fixtures.request("/x/..%2Fapp.js"), in: directory).status, 404)
        XCTAssertEqual(StaticFiles.file(Fixtures.request("/x/"), in: directory).status, 404)
        XCTAssertEqual(StaticFiles.file(Fixtures.request("/x/app.js", method: "POST"), in: directory).status, 404)
    }

    func testRejectsPercentEncodedTraversal() throws {
        // A secret sitting next to the served directory must not be reachable.
        let secret = directory.deletingLastPathComponent().appendingPathComponent("secret-\(UUID().uuidString).txt")
        try Data("secret".utf8).write(to: secret)
        defer { try? FileManager.default.removeItem(at: secret) }

        let encoded = [
            "%2e%2e%2f", "%2E%2E%2F", "%2e%2e/", "..%2f", "%2e%2e%5c", "%2e%2e%2f%2e%2e%2f",
        ]
        for prefix in encoded {
            let response = StaticFiles.file(Fixtures.request("/x/\(prefix)\(secret.lastPathComponent)"), in: directory)
            XCTAssertEqual(response.status, 404, prefix)
            XCTAssertNotEqual(response.text, "secret", prefix)
        }
        XCTAssertEqual(StaticFiles.file(Fixtures.request("/x/app.js%00.txt"), in: directory).status, 404)
        XCTAssertEqual(StaticFiles.file(Fixtures.request("/x/%2fetc%2fhosts"), in: directory).status, 404)
        XCTAssertEqual(StaticFiles.bundled(Fixtures.request("/local/static/%2e%2e%2fInfo.plist")).status, 404)
    }

    func testSafeNames() {
        XCTAssertTrue(StaticFiles.isSafeName("memories-main.js"))
        XCTAssertTrue(StaticFiles.isSafeName("00_server.css"))
        for bad in ["", "..", "a/b", "a\\b", "../x", "a..b", "a\u{0}b", "a\nb"] {
            XCTAssertFalse(StaticFiles.isSafeName(bad), bad)
        }
    }

    func testServesBundledOverrides() {
        let response = StaticFiles.bundled(Fixtures.request("/local/static/shell-overrides.css"))
        XCTAssertEqual(response.status, 200)
        XCTAssertEqual(response.header("Content-Type"), "text/css; charset=utf-8")
        XCTAssertEqual(StaticFiles.bundled(Fixtures.request("/local/static/nope.css")).status, 404)
    }
}
