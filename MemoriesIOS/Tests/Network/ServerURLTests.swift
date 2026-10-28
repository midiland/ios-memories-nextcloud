import XCTest
@testable import Memories

final class ServerURLTests: XCTestCase {
    func testBareHostDefaultsToHTTPSAndMemoriesPath() {
        let url = ServerURL(userInput: "cloud.example.com")
        XCTAssertEqual(url?.memoriesURL.absoluteString, "https://cloud.example.com/index.php/apps/memories/")
    }

    func testKeepsSchemePortAndSubfolder() {
        let url = ServerURL(userInput: "http://nas.local:8080/nextcloud")
        XCTAssertEqual(url?.memoriesURL.absoluteString, "http://nas.local:8080/nextcloud/index.php/apps/memories/")
    }

    func testDoesNotDuplicateExistingPath() {
        let url = ServerURL(userInput: "https://cloud.example.com/index.php/apps/memories")
        XCTAssertEqual(url?.memoriesURL.absoluteString, "https://cloud.example.com/index.php/apps/memories/")
    }

    func testStripsQueryFragmentAndWhitespace() {
        let url = ServerURL(userInput: "  https://cloud.example.com/?foo=1#bar \n")
        XCTAssertEqual(url?.memoriesURL.absoluteString, "https://cloud.example.com/index.php/apps/memories/")
    }

    func testUppercaseSchemeIsKept() {
        XCTAssertEqual(ServerURL(userInput: "HTTPS://cloud.example.com")?.host, "cloud.example.com")
    }

    func testRejectsEmptyInput() {
        XCTAssertNil(ServerURL(userInput: ""))
        XCTAssertNil(ServerURL(userInput: "   "))
        XCTAssertNil(ServerURL(userInput: "https://"))
    }

    func testDerivedPathsAtDomainRoot() {
        let url = ServerURL(userInput: "cloud.example.com")!
        XCTAssertEqual(url.webRoot, "")
        XCTAssertEqual(url.nextcloudRoot.absoluteString, "https://cloud.example.com/")
        XCTAssertEqual(url.appPath, "/index.php/apps/memories")
        XCTAssertEqual(url.appPaths, ["/index.php/apps/memories", "/apps/memories"])
        XCTAssertEqual(url.describeURL.absoluteString, "https://cloud.example.com/index.php/apps/memories/api/describe")
    }

    func testDerivedPathsInSubfolder() {
        let url = ServerURL(userInput: "https://example.fr:8443/nextcloud")!
        XCTAssertEqual(url.webRoot, "/nextcloud")
        XCTAssertEqual(url.nextcloudRoot.absoluteString, "https://example.fr:8443/nextcloud/")
        XCTAssertEqual(url.appPath, "/nextcloud/index.php/apps/memories")
        XCTAssertEqual(url.host, "example.fr")
        XCTAssertEqual(url.origin.absoluteString, "https://example.fr:8443")
    }

    func testBaseURLFromServerGetsTrailingSlash() {
        let url = ServerURL(memoriesBaseURL: "https://cloud.example.com/index.php/apps/memories")
        XCTAssertEqual(url?.memoriesURL.absoluteString, "https://cloud.example.com/index.php/apps/memories/")
        XCTAssertNil(ServerURL(memoriesBaseURL: "not a url"))
    }

    func testCodableRoundTrip() throws {
        let url = ServerURL(userInput: "cloud.example.com")!
        let decoded = try JSONDecoder().decode(ServerURL.self, from: JSONEncoder().encode(url))
        XCTAssertEqual(decoded, url)
    }

    func testServesPrettyURLsFollowsTheAnnouncedBaseURL() {
        XCTAssertTrue(ServerURL.servesPrettyURLs(baseUrl: "https://cloud.example.com/apps/memories/"))
        XCTAssertTrue(ServerURL.servesPrettyURLs(baseUrl: "https://cloud.example.com/nextcloud/apps/memories/"))
        XCTAssertFalse(ServerURL.servesPrettyURLs(baseUrl: "https://cloud.example.com/index.php/apps/memories/"))
        XCTAssertFalse(ServerURL.servesPrettyURLs(baseUrl: "https://cloud.example.com/nextcloud/index.php/apps/memories/"))
    }

    func testAppPathFollowsTheServerStyle() {
        XCTAssertEqual(ServerURL.appPath("/index.php/apps/memories/a/abc", prettyURLs: true, webRoot: ""), "/apps/memories/a/abc")
        XCTAssertEqual(ServerURL.appPath("/nc/index.php/apps/memories/a/abc", prettyURLs: true, webRoot: "/nc"), "/nc/apps/memories/a/abc")
        XCTAssertEqual(ServerURL.appPath("/apps/memories/a/abc", prettyURLs: false, webRoot: ""), "/index.php/apps/memories/a/abc")
        // Already in the right style, or outside the app, or only sharing a prefix: unchanged.
        XCTAssertEqual(ServerURL.appPath("/apps/memories/a/abc", prettyURLs: true, webRoot: ""), "/apps/memories/a/abc")
        XCTAssertEqual(ServerURL.appPath("/index.php/s/abc", prettyURLs: true, webRoot: ""), "/index.php/s/abc")
        XCTAssertEqual(ServerURL.appPath("/index.php/apps/memories-other/a", prettyURLs: true, webRoot: ""), "/index.php/apps/memories-other/a")
    }
}
