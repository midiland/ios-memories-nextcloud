import XCTest
@testable import Memories

final class NavigationPolicyTests: XCTestCase {
    private let filesPage = URL(string: "https://cloud.example.com/nextcloud/index.php/apps/files/")!

    private var policy: NavigationPolicy {
        NavigationPolicy(
            isLocal: { LocalOrigin.matches($0, localPort: 62079) },
            serverPage: { [filesPage] in $0.path.contains("/apps/files") ? filesPage : nil }
        )
    }

    private func url(_ text: String) -> URL { URL(string: text)! }

    func testAnotherLoopbackPortIsExternal() {
        let foreign = url("http://127.0.0.1:9999/")
        XCTAssertEqual(policy.decide(foreign), .external(foreign))
    }

    func testLocalAppPagesStay() {
        XCTAssertEqual(policy.decide(url("http://127.0.0.1:62079/nextcloud/index.php/apps/memories/")), .allow)
    }

    func testProxiedPathOpensTheRealPage() {
        let decision = policy.decide(url("http://127.0.0.1:62079/nextcloud/index.php/apps/files/"))
        XCTAssertEqual(decision, .external(filesPage))
    }

    func testServerPagesNeverLoadInTheWebView() {
        // Even the account's own server: its code is only loaded from the verified snapshot.
        let server = url("https://cloud.example.com/nextcloud/index.php/apps/memories/")
        XCTAssertEqual(policy.decide(server), .external(server))
    }

    func testOtherHostsOpenInSafari() {
        let other = url("https://www.openstreetmap.org/")
        XCTAssertEqual(policy.decide(other), .external(other))
    }

    func testNextcloudPlayStoreLinkOpensTheAppStore() {
        let play = url("https://play.google.com/store/apps/details?id=com.nextcloud.client")
        let appStore = url("https://apps.apple.com/app/nextcloud/id1125420102")
        XCTAssertEqual(policy.decide(play), .external(appStore))
    }

    func testOtherPlayStoreLinksAreKept() {
        let play = url("https://play.google.com/store/apps/details?id=gallery.memories")
        XCTAssertEqual(policy.decide(play), .external(play))
    }
}
