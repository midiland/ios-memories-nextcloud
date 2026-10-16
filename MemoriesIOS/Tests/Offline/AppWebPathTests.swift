import XCTest
@testable import Memories

final class AppWebPathTests: XCTestCase {
    /// Excerpt of the Memories page of a Nextcloud 34 Docker install, app in `custom_apps`.
    private let customAppsPage = """
    <script nonce="x" defer src="/custom_apps/memories/js/memories-main.js?v=8f3bd903-0"></script>
    <script nonce="x">window._oc_appswebroots={"activity":"/apps/activity","memories":"/custom_apps/memories","viewer":"/apps/viewer"};</script>
    """

    // MARK: - Page parsing

    func testReadsTheCustomAppsFolder() throws {
        let path = try XCTUnwrap(AppWebPath(pageHTML: customAppsPage))
        XCTAssertEqual(path.root, "/custom_apps/memories")
    }

    func testKeepsTheWebRoot() throws {
        let html = #"_oc_appswebroots={"memories":"/nextcloud/custom_apps/memories"}"#
        XCTAssertEqual(AppWebPath(pageHTML: html)?.root, "/nextcloud/custom_apps/memories")
    }

    func testUnescapesJSONSlashes() throws {
        let html = #"_oc_appswebroots={"memories":"\/custom_apps\/memories"}"#
        XCTAssertEqual(AppWebPath(pageHTML: html)?.root, "/custom_apps/memories")
    }

    func testIgnoresMemoriesMentionsBeforeTheWebRoots() throws {
        let html = #""memories":"/elsewhere/memories" _oc_appswebroots={"memories":"/custom_apps/memories"}"#
        XCTAssertEqual(AppWebPath(pageHTML: html)?.root, "/custom_apps/memories")
    }

    func testMissingEntryGivesNil() {
        XCTAssertNil(AppWebPath(pageHTML: "<html>no web roots</html>"))
        XCTAssertNil(AppWebPath(pageHTML: #"_oc_appswebroots={"photos":"/apps/photos"}"#))
    }

    func testRejectsAnythingButAPlainPath() {
        for root in ["https://evil.example/memories", "//evil.example/memories", "/custom_apps/../memories",
                     "custom_apps/memories", "/custom apps/memories", "/", "/custom_apps//memories"] {
            XCTAssertNil(AppWebPath(pageHTML: #"_oc_appswebroots={"memories":"\#(root)"}"#), root)
        }
    }

    // MARK: - Resolution

    func testMovesManifestHrefsToTheRealFolder() throws {
        let path = try XCTUnwrap(AppWebPath(pageHTML: customAppsPage))
        XCTAssertEqual(
            path.resolve("/apps/memories/js/memories-main.js?v=abc"),
            "/custom_apps/memories/js/memories-main.js?v=abc"
        )
    }

    func testLeavesOtherHrefsUnchanged() throws {
        let path = try XCTUnwrap(AppWebPath(pageHTML: customAppsPage))
        XCTAssertEqual(path.resolve("/nextcloud/apps/memories/js/a.js"), "/nextcloud/apps/memories/js/a.js")
        XCTAssertEqual(path.resolve("/apps/memories-extra/js/a.js"), "/apps/memories-extra/js/a.js")
        XCTAssertEqual(path.resolve("https://cdn.example/a.js"), "https://cdn.example/a.js")
    }

    func testFallbackUsesTheWebRoot() {
        XCTAssertEqual(AppWebPath(webRoot: "").resolve("/apps/memories/js/a.js"), "/apps/memories/js/a.js")
        XCTAssertEqual(AppWebPath(webRoot: "/nextcloud").resolve("/apps/memories/js/a.js"), "/nextcloud/apps/memories/js/a.js")
    }
}
