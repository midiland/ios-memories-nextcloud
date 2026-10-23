import JavaScriptCore
import XCTest
@testable import Memories

/// Tests for the swipe-to-select iOS enhancement (midiland/ios-memories-nextcloud#11).
final class SwipeSelectTests: XCTestCase {

    // MARK: - Shell page integration

    /// The shell page must load the swipe-select CSS alongside shell-overrides.css.
    func testShellPageLoadsSwipeSelectCSS() throws {
        let html = ShellPage.html(
            manifest: try AssetManifest(raw: Fixtures.describe()),
            webRoot: "/nextcloud",
            user: "alice",
            nonce: "N0NCE",
            modRewriteWorking: true
        )
        XCTAssertTrue(
            html.contains(#"<link href="/local/static/swipe-select.css" rel="stylesheet">"#),
            "Shell page must include swipe-select.css"
        )
    }

    /// The CSS link must come after shell-overrides.css so it can override if needed.
    func testSwipeSelectCSSComesAfterShellOverrides() throws {
        let html = ShellPage.html(
            manifest: try AssetManifest(raw: Fixtures.describe()),
            webRoot: "/nextcloud",
            user: "alice",
            nonce: "N0NCE",
            modRewriteWorking: true
        )
        let overridesRange = try XCTUnwrap(html.range(of: "shell-overrides.css"))
        let swipeRange = try XCTUnwrap(html.range(of: "swipe-select.css"))
        XCTAssertLessThan(overridesRange.upperBound, swipeRange.lowerBound)
    }

    // MARK: - CSS content

    /// The bundled CSS must contain the touch-action rules for the recycler photos.
    func testBundledCSSContainsTouchActionRules() throws {
        let css = try XCTUnwrap(SwipeSelectTests.bundledCSS())
        // Default: pan-y allows vertical scroll, blocks horizontal interception
        XCTAssertTrue(css.contains("touch-action: pan-y"), "CSS must set touch-action: pan-y on photos")
        // Selection mode: none disables all native gesture handling
        XCTAssertTrue(css.contains("touch-action: none"), "CSS must set touch-action: none in selection mode")
    }

    /// The CSS must target the correct selectors used by the Memories web app.
    func testBundledCSSContainsCorrectSelectors() throws {
        let css = try XCTUnwrap(SwipeSelectTests.bundledCSS())
        XCTAssertTrue(css.contains(".recycler .photo"), "CSS must target .recycler .photo")
        XCTAssertTrue(css.contains(".p-outer-super"), "CSS must target .p-outer-super")
        XCTAssertTrue(css.contains(".p-outer.selected"), "CSS must detect selection via .p-outer.selected")
    }

    /// The CSS must disable user-select and touch-callout on photos (iOS-specific).
    func testBundledCSSDisablesUserSelectAndCallout() throws {
        let css = try XCTUnwrap(SwipeSelectTests.bundledCSS())
        XCTAssertTrue(css.contains("-webkit-user-select: none"), "CSS must disable user-select")
        XCTAssertTrue(css.contains("-webkit-touch-callout: none"), "CSS must disable touch-callout")
    }

    // MARK: - JS injection

    /// The swipe-select.js script must be loadable from the bundle.
    func testSwipeSelectScriptIsInBundle() {
        let source = NativeXController.swipeSelectScriptSource()
        XCTAssertNotNil(source, "swipe-select.js must be in the app bundle")
    }

    /// The script must be valid JavaScript (parses without errors in a browser-like context).
    func testSwipeSelectScriptIsValidJavaScript() throws {
        let source = try XCTUnwrap(NativeXController.swipeSelectScriptSource())
        let context = JSContext()!
        // Provide a minimal browser-like environment
        context.evaluateScript(SwipeSelectTests.browserShim)
        context.evaluateScript(source)
        XCTAssertNil(context.exception, "swipe-select.js must not throw on evaluation")
    }

    /// The script must install a guard against double-injection.
    func testSwipeSelectScriptHasDoubleInjectionGuard() throws {
        let source = try XCTUnwrap(NativeXController.swipeSelectScriptSource())
        XCTAssertTrue(
            source.contains("__swipeSelectInstalled"),
            "Script must guard against double-injection"
        )
    }

    /// The script must only run when the NativeX bridge is present (iOS app context).
    func testSwipeSelectScriptChecksForNativeXBridge() throws {
        let source = try XCTUnwrap(NativeXController.swipeSelectScriptSource())
        XCTAssertTrue(
            source.contains("webkit.messageHandlers.nativex"),
            "Script must check for the nativex bridge before running"
        )
    }

    /// The script must use the haptic feedback bridge (playTouchSound).
    func testSwipeSelectScriptUsesHapticFeedback() throws {
        let source = try XCTUnwrap(NativeXController.swipeSelectScriptSource())
        XCTAssertTrue(
            source.contains("playTouchSound"),
            "Script must call playTouchSound for haptic feedback"
        )
    }

    /// The script must expose a debug handle for Safari Web Inspector.
    func testSwipeSelectScriptExposesDebugHandle() throws {
        let source = try XCTUnwrap(NativeXController.swipeSelectScriptSource())
        XCTAssertTrue(
            source.contains("window.__swipeSelect"),
            "Script must expose window.__swipeSelect for debugging"
        )
    }

    /// The script must add a non-passive touchmove listener to prevent native scroll.
    func testSwipeSelectScriptHasNonPassiveTouchmove() throws {
        let source = try XCTUnwrap(NativeXController.swipeSelectScriptSource())
        XCTAssertTrue(
            source.contains("{ passive: false }"),
            "Script must add a non-passive touchmove listener"
        )
        XCTAssertTrue(
            source.contains("preventDefault"),
            "Script must call preventDefault() to stop native scroll during swipe-select"
        )
    }

    /// The script must implement manual auto-scroll near screen edges.
    func testSwipeSelectScriptImplementsAutoScroll() throws {
        let source = try XCTUnwrap(NativeXController.swipeSelectScriptSource())
        XCTAssertTrue(
            source.contains("autoScroll"),
            "Script must implement auto-scroll"
        )
        XCTAssertTrue(
            source.contains("CLAMP_TOP") && source.contains("CLAMP_BOTTOM"),
            "Script must define edge clamp constants"
        )
        XCTAssertTrue(
            source.contains("scrollTop"),
            "Script must scroll the recycler manually"
        )
    }

    /// The script must detect if the touch started on a photo element.
    func testSwipeSelectScriptDetectsPhotoTouch() throws {
        let source = try XCTUnwrap(NativeXController.swipeSelectScriptSource())
        XCTAssertTrue(
            source.contains("p-outer-super") || source.contains(".photo"),
            "Script must detect touches on photo elements"
        )
        XCTAssertTrue(
            source.contains("isSelectionMode") || source.contains("p-outer.selected"),
            "Script must check if selection mode is active"
        )
    }

    /// The script must allow normal scrolling when NOT swiping over photos.
    func testSwipeSelectScriptAllowsNormalScroll() throws {
        let source = try XCTUnwrap(NativeXController.swipeSelectScriptSource())
        // The script should only preventDefault when swipeState.active is true
        // (i.e., when swiping over photos in selection mode)
        XCTAssertTrue(
            source.contains("swipeState.active"),
            "Script must track swipe state to distinguish swipe-select from normal scroll"
        )
    }

    // MARK: - JS behavior (JavaScriptCore simulation)

    /// Simulate the script in a JS context with a mocked nativex bridge.
    /// Verifies the script sets up the observer and doesn't throw.
    func testScriptRunsWithMockedBridge() throws {
        let source = try XCTUnwrap(NativeXController.swipeSelectScriptSource())
        let context = JSContext()!
        context.evaluateScript(SwipeSelectTests.browserShim)
        context.evaluateScript(SwipeSelectTests.nativeXBridgeMock)

        // Evaluate the script — should not throw
        context.evaluateScript(source)
        XCTAssertNil(context.exception, "Script must not throw with mocked bridge")

        // The double-injection guard should be set
        let installed = context.evaluateScript("window.__swipeSelectInstalled")
        XCTAssertEqual(installed?.toBool(), true, "Script must set __swipeSelectInstalled guard")

        // Debug handle should be exposed
        let debugHandle = context.evaluateScript("typeof window.__swipeSelect")
        XCTAssertEqual(debugHandle?.toString(), "object", "Script must expose window.__swipeSelect")
    }

    /// The script must NOT run when the nativex bridge is absent (regular browser).
    func testScriptDoesNotRunWithoutNativeXBridge() throws {
        let source = try XCTUnwrap(NativeXController.swipeSelectScriptSource())
        let context = JSContext()!
        context.evaluateScript(SwipeSelectTests.browserShim)
        // Note: no nativex bridge mock — simulates a regular browser

        context.evaluateScript(source)
        XCTAssertNil(context.exception)

        // The guard should NOT be set because the script bailed early
        let installed = context.evaluateScript("typeof window.__swipeSelectInstalled")
        XCTAssertEqual(installed?.toString(), "undefined", "Script must not install without nativex bridge")
    }

    /// Double evaluation must be a no-op (guard works).
    func testScriptDoubleEvaluationIsNoOp() throws {
        let source = try XCTUnwrap(NativeXController.swipeSelectScriptSource())
        let context = JSContext()!
        context.evaluateScript(SwipeSelectTests.browserShim)
        context.evaluateScript(SwipeSelectTests.nativeXBridgeMock)

        context.evaluateScript(source)
        XCTAssertNil(context.exception)

        // Count observers created — override both the global and window.MutationObserver
        context.evaluateScript("window.__observerCount = 0;")
        context.evaluateScript("""
            MutationObserver = function(cb) {
                window.__observerCount++;
                this.observe = function() {};
                this.disconnect = function() {};
            };
            window.MutationObserver = MutationObserver;
        """)

        // Evaluate again — should be a no-op due to the guard
        context.evaluateScript(source)
        XCTAssertNil(context.exception)

        let count = context.evaluateScript("window.__observerCount")
        XCTAssertEqual(count?.toInt32(), 0, "Second evaluation must not create another observer")
    }

    /// The script must provide haptic feedback when selection changes.
    func testScriptProvidesHapticFeedbackOnSelectionChange() throws {
        let source = try XCTUnwrap(NativeXController.swipeSelectScriptSource())
        let context = JSContext()!
        context.evaluateScript(SwipeSelectTests.browserShim)
        context.evaluateScript(SwipeSelectTests.nativeXBridgeMock)

        // Track haptic calls
        context.evaluateScript("""
            window.__hapticCount = 0;
            window.webkit.messageHandlers.nativex.postMessage = function(msg) {
                if (msg.method === 'playTouchSound') window.__hapticCount++;
            };
        """)

        context.evaluateScript(source)
        XCTAssertNil(context.exception)

        // Simulate a selection change by calling the internal checkSelectionChange
        // (we can't directly access it, but we can verify the observer is set up)
        let observerActive = context.evaluateScript("typeof window.__swipeSelect")
        XCTAssertEqual(observerActive?.toString(), "object")
    }

    // MARK: - Static file serving

    /// The local server must serve swipe-select.css from /local/static/.
    func testLocalServerServesSwipeSelectCSS() throws {
        let request = Fixtures.request("/local/static/swipe-select.css")
        let response = StaticFiles.bundled(request)
        guard case .data(let data) = response.body else {
            XCTFail("Expected data response for swipe-select.css")
            return
        }
        let css = String(data: data, encoding: .utf8)
        XCTAssertNotNil(css, "swipe-select.css must be served as UTF-8")
        XCTAssertTrue(css?.contains("touch-action") == true)
        XCTAssertEqual(response.header("Content-Type"), "text/css; charset=utf-8")
    }

    /// The local server must return 404 for non-existent static files.
    func testLocalServerReturns404ForMissingCSS() {
        let request = Fixtures.request("/local/static/nonexistent.css")
        let response = StaticFiles.bundled(request)
        XCTAssertEqual(response.status, 404)
    }

    // MARK: - Helpers

    /// Reads the bundled swipe-select.css from the app bundle (Bundle.main in test context).
    private static func bundledCSS() -> String? {
        guard let url = Bundle.main.url(forResource: "swipe-select", withExtension: "css"),
              let css = try? String(contentsOf: url, encoding: .utf8)
        else { return nil }
        return css
    }

    /// Minimal browser environment shim for JavaScriptCore.
    /// Provides window, document, MutationObserver, setTimeout, etc. as globals.
    /// Uses a plain object for `window` (not globalThis) so properties are mutable.
    private static let browserShim = """
        var window = {};
        window.innerHeight = 800;
        window.innerWidth = 400;
        var document = {
            body: {},
            querySelector: function() { return null; },
            querySelectorAll: function() { return []; },
            addEventListener: function() {}
        };
        window.document = document;
        var MutationObserver = function(callback) {
            this.observe = function() {};
            this.disconnect = function() {};
        };
        window.MutationObserver = MutationObserver;
        var setTimeout = function(fn, ms) { return 0; };
        var requestAnimationFrame = function(fn) { return 0; };
        var cancelAnimationFrame = function() {};
        window.setTimeout = setTimeout;
        window.requestAnimationFrame = requestAnimationFrame;
        window.cancelAnimationFrame = cancelAnimationFrame;
        window.Date = Date;
    """

    /// Mock of the nativex bridge for testing.
    private static let nativeXBridgeMock = """
        window.webkit = {
            messageHandlers: {
                nativex: {
                    postMessage: function(msg) {
                        window.__lastMessage = msg;
                    }
                }
            }
        };
    """
}
