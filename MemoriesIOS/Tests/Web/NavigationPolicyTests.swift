import XCTest
@testable import Memories

final class NavigationPolicyTests: XCTestCase {
    private let filesPage = URL(string: "https://cloud.example.com/nextcloud/index.php/apps/files/")!

    private func policy(_ mode: NavigationPolicy.Mode) -> NavigationPolicy {
        NavigationPolicy(
            mode: mode,
            serverHost: "cloud.example.com",
            isLocal: { $0.host == "127.0.0.1" },
            serverPage: { [filesPage] in $0.path.contains("/apps/files") ? filesPage : nil }
        )
    }

    private func url(_ text: String) -> URL { URL(string: text)! }

    // MARK: - Local mode

    func testLocalAppPagesStay() {
        XCTAssertEqual(policy(.local).decide(url("http://127.0.0.1:62079/nextcloud/index.php/apps/memories/")), .allow)
    }

    func testLocalProxiedPathOpensTheRealPage() {
        let decision = policy(.local).decide(url("http://127.0.0.1:62079/nextcloud/index.php/apps/files/"))
        XCTAssertEqual(decision, .external(filesPage))
    }

    func testLocalModeSendsOtherHostsToSafari() {
        let other = url("https://cloud.example.com/nextcloud/index.php/apps/memories/")
        XCTAssertEqual(policy(.local).decide(other), .external(other))
    }

    // MARK: - Remote mode

    func testRemoteServerPagesStay() {
        XCTAssertEqual(policy(.remote).decide(url("https://cloud.example.com/nextcloud/index.php/apps/memories/")), .allow)
    }

    func testRemoteModeSendsOtherHostsToSafari() {
        let other = url("https://www.openstreetmap.org/")
        XCTAssertEqual(policy(.remote).decide(other), .external(other))
    }

    func testRemoteLoginPageMeansSessionLost() {
        XCTAssertEqual(policy(.remote).decide(url("https://cloud.example.com/nextcloud/index.php/login?redirect_url=x")), .sessionLost)
    }

    // MARK: - Login page detection

    func testLoginPageDetection() {
        XCTAssertTrue(NavigationPolicy.isLoginPage(url("https://c/login")))
        XCTAssertTrue(NavigationPolicy.isLoginPage(url("https://c/index.php/login/")))
        XCTAssertTrue(NavigationPolicy.isLoginPage(url("https://c/index.php/login/challenge/totp")))
        XCTAssertTrue(NavigationPolicy.isLoginPage(url("https://c/index.php/login/selectchallenge")))
        // Login Flow v2 must not be mistaken for an expired session.
        XCTAssertFalse(NavigationPolicy.isLoginPage(url("https://c/index.php/login/v2/flow/abc")))
        XCTAssertFalse(NavigationPolicy.isLoginPage(url("https://c/index.php/apps/memories/")))
    }
}
