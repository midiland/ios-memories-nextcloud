import XCTest
@testable import Memories

final class RequestHelpersTests: XCTestCase {
    func testBasicAuthHeader() {
        // base64("alice:secret")
        XCTAssertEqual(Fixtures.credentials.basicAuthHeader, "Basic YWxpY2U6c2VjcmV0")
    }

    func testCredentialsAreSentToTheAccountHost() {
        let request = URLRequest(url: URL(string: "https://cloud.example.com/remote.php/x")!, authorizedFor: Fixtures.credentials)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Basic YWxpY2U6c2VjcmV0")
        XCTAssertEqual(request.value(forHTTPHeaderField: "OCS-APIREQUEST"), "true")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), AppConstants.userAgentSuffix)
    }

    func testCredentialsAreNeverSentToAnotherHost() {
        let request = URLRequest(url: URL(string: "https://evil.example.org/file")!, authorizedFor: Fixtures.credentials)
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(request.value(forHTTPHeaderField: "OCS-APIREQUEST"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), AppConstants.userAgentSuffix)
    }

    // MARK: - Local server (downloads built by the frontend on the page origin)

    private let local = LocalServerAccess(port: 62079, secret: "s3cr3t")

    func testLocalServerURLsCarryTheAccessCookieButNoCredentials() {
        let url = URL(string: "http://127.0.0.1:62079/index.php/apps/memories/api/stream/78?attachment=1")!
        let request = URLRequest(url: url, authorizedFor: Fixtures.credentials, localServer: local)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), "local-auth=s3cr3t")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"), "the local server adds them upstream")
    }

    func testAccessCookieOnlyGoesToTheLocalServerPort() {
        for text in ["http://127.0.0.1:8080/x", "http://127.0.0.1/x", "https://127.0.0.1:62079/x",
                     "http://evil.example.org:62079/x", "https://cloud.example.com/x"] {
            let request = URLRequest(url: URL(string: text)!, authorizedFor: Fixtures.credentials, localServer: local)
            XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"), text)
        }
        XCTAssertTrue(local.covers(URL(string: "http://localhost:62079/x")!))
    }

    func testNoAccessCookieWithoutALocalServer() {
        let request = URLRequest(url: URL(string: "http://127.0.0.1:62079/x")!, authorizedFor: Fixtures.credentials)
        XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
    }

    func testUserAgentAdvertisesNativeMode() {
        XCTAssertTrue(AppConstants.userAgentSuffix.hasPrefix("MemoriesNative/\(AppConstants.nativeXVersion) MemoriesIOS/"))
    }

    func testAppErrorFromKeepsAppErrors() {
        XCTAssertEqual(AppError.from(AppError.loginTimeout), .loginTimeout)
    }

    func testAppErrorFromWrapsOtherErrors() {
        guard case .serverUnreachable = AppError.from(URLError(.notConnectedToInternet)) else {
            return XCTFail("expected serverUnreachable")
        }
    }
}
