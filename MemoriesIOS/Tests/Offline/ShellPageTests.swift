import XCTest
@testable import Memories

final class ShellPageTests: XCTestCase {
    private func html(webRoot: String = "/nextcloud", user: String? = "alice") throws -> String {
        ShellPage.html(manifest: try AssetManifest(raw: Fixtures.describe()), webRoot: webRoot, user: user, nonce: "N0NCE")
    }

    func testLinksPointToLocalStylesheets() throws {
        let page = try html()
        XCTAssertTrue(page.contains(#"<link href="/local/assets/css/00_server.css" media="screen" rel="stylesheet">"#))
        XCTAssertTrue(page.contains(#"<link href="/local/assets/css/01_memories-main.css" rel="stylesheet">"#))
        XCTAssertTrue(page.contains(#"<link href="/local/static/shell-overrides.css" rel="stylesheet">"#))
    }

    func testLoadsLocalScriptsWithNonce() throws {
        let page = try html()
        XCTAssertTrue(page.contains(#"<script src="/local/assets/js/memories-l10n.js"></script>"#))
        XCTAssertTrue(page.contains(#"<script src="/local/assets/js/memories-main.js" defer></script>"#))
        XCTAssertTrue(page.contains(#"<script nonce="N0NCE">"#))
        XCTAssertTrue(page.contains("window._oc_webroot = '/nextcloud';"))
    }

    func testEscapesUserAndWebRoot() throws {
        let page = try html(webRoot: "/a'b<c", user: #"x"><script>"#)
        XCTAssertTrue(page.contains(#"<head data-user="x&quot;&gt;&lt;script&gt;">"#))
        XCTAssertTrue(page.contains(#"window._oc_webroot = '/a\'b\x3cc';"#))
    }

    func testOmitsUserAttributeWhenUnknown() throws {
        XCTAssertTrue(try html(user: nil).contains("<head>"))
    }

    func testCSPAllowsOnlyTheNonceForInlineScripts() {
        let csp = ShellPage.csp(nonce: "N0NCE")
        XCTAssertTrue(csp.contains("script-src 'self' blob: 'nonce-N0NCE'"))
        XCTAssertTrue(csp.contains("object-src 'none'"))
        XCTAssertFalse(csp.contains("'unsafe-eval'"))
    }
}
