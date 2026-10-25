import XCTest
@testable import Memories

final class LoginURLPolicyTests: XCTestCase {
    private let https = ServerURL(userInput: "https://cloud.example.com/nextcloud")!
    private let http = ServerURL(userInput: "http://cloud.local:8080")!

    private func ok(_ text: String, for server: ServerURL) -> Bool {
        LoginURLPolicy.isAcceptable(URL(string: text)!, for: server)
    }

    func testAcceptsWebURLsOnTheServerHost() {
        XCTAssertTrue(ok("https://cloud.example.com/index.php/login/v2/flow/abc", for: https))
        XCTAssertTrue(ok("https://CLOUD.example.com:8443/login/v2/poll", for: https))
        XCTAssertTrue(ok("http://cloud.local:8080/index.php/login/v2", for: http))
        XCTAssertTrue(ok("https://cloud.local/login", for: http)) // upgrading to https is fine
    }

    func testRejectsOtherSchemes() {
        // `SFSafariViewController(url:)` raises an exception for these.
        for text in ["file:///etc/hosts", "javascript:alert(1)", "data:text/html,hi", "tel:123", "myapp://login"] {
            XCTAssertFalse(ok(text, for: https), text)
        }
    }

    func testRejectsOtherHostsAndDowngrades() {
        XCTAssertFalse(ok("https://evil.example.org/login", for: https))
        XCTAssertFalse(ok("https://cloud.example.com.evil.org/login", for: https))
        XCTAssertFalse(ok("https://cloud.example.com@evil.example.org/login", for: https))
        XCTAssertFalse(ok("http://cloud.example.com/login", for: https)) // downgrade
    }

    func testCanonicalServerStaysOnTheEnteredHost() throws {
        let same = try XCTUnwrap(LoginURLPolicy.canonicalServer(
            baseUrl: "https://cloud.example.com/index.php/apps/memories/", entered: https
        ))
        XCTAssertEqual(same.origin.host, "cloud.example.com")
        XCTAssertNil(LoginURLPolicy.canonicalServer(baseUrl: "https://evil.example.org/index.php/apps/memories/", entered: https))
        XCTAssertNil(LoginURLPolicy.canonicalServer(baseUrl: "http://cloud.example.com/index.php/apps/memories/", entered: https))
        XCTAssertNil(LoginURLPolicy.canonicalServer(baseUrl: "file:///index.php/apps/memories/", entered: https))
    }
}
