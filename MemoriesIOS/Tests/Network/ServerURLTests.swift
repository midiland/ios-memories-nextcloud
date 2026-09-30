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
}
