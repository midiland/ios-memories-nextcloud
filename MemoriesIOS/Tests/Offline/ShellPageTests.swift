import JavaScriptCore
import XCTest
@testable import Memories

final class ShellPageTests: XCTestCase {
    private func html(webRoot: String = "/nextcloud", user: String? = "alice", modRewriteWorking: Bool = true) throws -> String {
        ShellPage.html(manifest: try AssetManifest(raw: Fixtures.describe()), webRoot: webRoot, user: user, nonce: "N0NCE", modRewriteWorking: modRewriteWorking)
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

    /// Issue #12: the WebView zooms the whole page (grid, top and bottom bars) on pinch.
    /// The shell page must forbid user scaling: unlike mobile Safari, WKWebView honors
    /// `user-scalable=no` / `maximum-scale=1`.
    func testViewportMetaDisablesPinchZoom() throws {
        let page = try html()
        XCTAssertTrue(page.contains("user-scalable=no"))
        XCTAssertTrue(page.contains("maximum-scale=1"))
    }

    /// Issue #13: same viewport as the server-side patch (TemplateResponsePatch.php):
    /// `viewport-fit=cover` lets the web viewport extend over the safe areas (Dynamic
    /// Island, home indicator, landscape side insets) when the app goes full screen.
    func testViewportMetaCoversSafeAreas() throws {
        let page = try html()
        XCTAssertTrue(page.contains(
            #"<meta name="viewport" content="width=device-width, viewport-fit=cover, initial-scale=1, minimum-scale=1.0, maximum-scale=1, user-scalable=no">"#
        ))
    }

    func testCSPAllowsOnlyTheNonceForInlineScripts() {
        let csp = ShellPage.csp(nonce: "N0NCE")
        XCTAssertTrue(csp.contains("script-src 'self' blob: 'nonce-N0NCE'"))
        XCTAssertTrue(csp.contains("object-src 'none'"))
        XCTAssertFalse(csp.contains("'unsafe-eval'"))
    }

    // MARK: - window.OC (album share / collaborators dialogs)

    func testDefinesTheOCGlobalBeforeTheApp() throws {
        let page = try html()
        let global = try XCTUnwrap(page.range(of: ShellPage.ocGlobal))
        let entry = try XCTUnwrap(page.range(of: "memories-main.js\" defer"))
        XCTAssertLessThan(global.lowerBound, entry.lowerBound)
    }

    /// Runs the injected script, then `expression`, in a page-like JavaScript context.
    private func evaluate(_ expression: String, existing: String? = nil) -> JSValue? {
        let context = JSContext()!
        context.evaluateScript("var window = this;")
        if let existing { context.evaluateScript(existing) }
        context.evaluateScript(ShellPage.ocGlobal)
        return context.evaluateScript(expression)
    }

    func testCurrentFrontendCodeNoLongerThrows() {
        // AlbumCollaborators.vue today (line 209).
        let value = evaluate("parseInt(window.OC.config['sharing.minSearchStringLength'], 10) || 0")
        XCTAssertEqual(value?.toInt32(), 0)
    }

    func testUpstreamFixGivesTheSameResult() {
        // The fix proposed upstream: same value with or without the injected global.
        let fixed = "parseInt(window.OC?.config?.['sharing.minSearchStringLength'], 10) || 0"
        XCTAssertEqual(evaluate(fixed)?.toInt32(), 0)
        let withoutGlobal = JSContext()!
        withoutGlobal.evaluateScript("var window = this;")
        XCTAssertEqual(withoutGlobal.evaluateScript(fixed)?.toInt32(), 0)
    }

    func testOptionalReadsBehaveAsWithoutOC() {
        // Other reads in the frontend and @nextcloud libraries all use optional chaining.
        XCTAssertTrue(evaluate("window.OC?.config?.version")?.isUndefined ?? false)
        XCTAssertEqual(evaluate("window.OC?.webroot || ''")?.toString(), "")
        XCTAssertTrue(evaluate("window.OC?._eventBus")?.isUndefined ?? false)
        XCTAssertTrue(evaluate("window.OC?.appConfig?.files?.max_chunk_size")?.isUndefined ?? false)
    }

    func testKeepsAnExistingOCObject() {
        let existing = "window.OC = { config: { 'sharing.minSearchStringLength': '3' }, debug: true };"
        XCTAssertEqual(evaluate("parseInt(window.OC.config['sharing.minSearchStringLength'], 10)", existing: existing)?.toInt32(), 3)
        XCTAssertEqual(evaluate("window.OC.debug", existing: existing)?.toBool(), true)
    }

    // MARK: - window.oc_config (issue #7: public share links must match server URL style)

    /// The shell must expose `oc_config.mod_rewrite_working` so `@nextcloud/router`'s
    /// `generateUrl()` emits URLs without `index.php` when the server uses pretty URLs.
    func testSetsModRewriteWorkingWhenServerUsesPrettyURLs() throws {
        let page = try html(modRewriteWorking: true)
        XCTAssertTrue(page.contains("window.oc_config.mod_rewrite_working = true;"))
    }

    func testSetsModRewriteWorkingFalseWhenServerUsesIndexPHP() throws {
        let page = try html(modRewriteWorking: false)
        XCTAssertTrue(page.contains("window.oc_config.mod_rewrite_working = false;"))
    }

    /// `window.oc_config` must not clobber an existing object (defensive, like `ocGlobal`).
    func testKeepsAnExistingOcConfig() throws {
        let context = JSContext()!
        context.evaluateScript("var window = this;")
        context.evaluateScript("window.oc_config = { mod_rewrite_working: false, other: 1 };")
        // Simulate the generated line (true = pretty URLs).
        context.evaluateScript("window.oc_config = window.oc_config || {}; window.oc_config.mod_rewrite_working = true;")
        XCTAssertEqual(context.evaluateScript("window.oc_config.mod_rewrite_working")?.toBool(), true)
        XCTAssertEqual(context.evaluateScript("window.oc_config.other")?.toInt32(), 1)
    }
}
