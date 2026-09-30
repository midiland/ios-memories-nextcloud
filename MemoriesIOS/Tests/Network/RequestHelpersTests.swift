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
