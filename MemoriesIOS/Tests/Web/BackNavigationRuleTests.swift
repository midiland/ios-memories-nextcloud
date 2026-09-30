import XCTest
@testable import Memories

final class BackNavigationRuleTests: XCTestCase {
    private func shows(_ path: String, canGoBack: Bool = true) -> Bool {
        BackNavigationRule.showsBackButton(
            url: URL(string: "http://127.0.0.1:62079" + path), canGoBack: canGoBack, server: Fixtures.server
        )
    }

    func testHiddenOnMainTabs() {
        for path in ["/nextcloud/index.php/apps/memories/", "/nextcloud/index.php/apps/memories",
                     "/nextcloud/index.php/apps/memories/explore", "/nextcloud/apps/memories/albums/"] {
            XCTAssertFalse(shows(path), path)
        }
    }

    func testShownOnPagesWithoutWebNavigation() {
        for path in ["/nextcloud/index.php/apps/memories/thisday", "/nextcloud/index.php/apps/memories/favorites",
                     "/nextcloud/index.php/apps/memories/recognize/alice/12", "/nextcloud/index.php/apps/memories/albums/alice/trip"] {
            XCTAssertTrue(shows(path), path)
        }
    }

    func testHiddenWithoutHistoryOrWithFragment() {
        XCTAssertFalse(shows("/nextcloud/index.php/apps/memories/thisday", canGoBack: false))
        XCTAssertFalse(shows("/nextcloud/index.php/apps/memories/thisday#v/123"))
        XCTAssertFalse(BackNavigationRule.showsBackButton(url: nil, canGoBack: true, server: Fixtures.server))
    }
}
