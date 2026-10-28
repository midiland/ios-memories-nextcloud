import JavaScriptCore
import XCTest
@testable import Memories

/// `nativex.js` run in JavaScriptCore with a fake page: which requests go to the native bridge.
///
/// In local mode the page itself is served from `127.0.0.1:62079`: only the bridge routes
/// (`/api/...` at the root) may be diverted, everything else must reach the local server
/// (diverting HLS playlists and segments made videos load forever).
final class NativeXScriptTests: XCTestCase {
    private let origin = "http://127.0.0.1:62079"
    private var context: JSContext!

    override func setUpWithError() throws {
        context = JSContext()
        context.exceptionHandler = { _, exception in
            XCTFail("JavaScript error: \(exception?.toString() ?? "?")")
        }
        // Fake page: records bridge messages and real network calls.
        context.evaluateScript("""
            var window = globalThis;
            var bridged = [], fetched = [], opened = [], posted = [];
            var observerCallbacks = [], domReady = [];
            window.webkit = { messageHandlers: {
                nativex: { postMessage: (m) => posted.push(m) },
                nativexAsync: { postMessage: (m) => {
                    bridged.push(m.url);
                    return Promise.resolve({ status: 200, contentType: 'application/json', body: '[]' });
                } },
            } };
            var document = {
                head: { appendChild: () => {} },
                body: null,
                createElement: () => ({}),
                querySelector: () => null,
                addEventListener: (type, fn) => { if (type === 'DOMContentLoaded') domReady.push(fn); },
            };
            var MutationObserver = class {
                constructor(cb) { observerCallbacks.push(cb); }
                observe() {}
            };
            window.fetch = (input) => { fetched.push(String(input)); return Promise.resolve(null); };
            function XMLHttpRequest() {}
            XMLHttpRequest.prototype.open = function (method, url) { opened.push(String(url)); };
            XMLHttpRequest.prototype.send = function () {};
            XMLHttpRequest.prototype.setRequestHeader = function () {};
            XMLHttpRequest.prototype.dispatchEvent = function () {};
            function ProgressEvent(type) { this.type = type; }
            function Request() {}
            function Response() {}
            if (typeof URL === 'undefined') { var URL = function () {}; }
            """)
        let source = try XCTUnwrap(NativeXController.scriptSource(state: [:]), "nativex.js not in the app bundle")
        context.evaluateScript(source)
        XCTAssertTrue(context.evaluateScript("typeof window.nativex === 'object'").toBool())
    }

    func testBridgeReportsTheIOSPlatform() {
        XCTAssertEqual(context.evaluateScript("window.nativex.getPlatform()").toString(), "ios")
    }

    // MARK: - Bridge routes

    func testBridgeRoutesAreDivertedOnTheLocalOrigin() {
        for path in ["/api/days", "/api/days/19000", "/api/image/info/42", "/api/config/allow_media/1", "/api/share/blobs"] {
            XCTAssertEqual(fetch(origin + path), .bridge, path)
            XCTAssertEqual(xhr(origin + path), .bridge, path)
        }
    }

    func testBridgeRoutesAreDivertedOnTheDefaultPort() {
        // Without a port: the frontend's default BASE_URL when the page is not served from 127.0.0.1.
        XCTAssertEqual(fetch("http://127.0.0.1/api/days"), .bridge)
        XCTAssertEqual(xhr("http://localhost/api/share/url/x"), .bridge)
    }

    // MARK: - Everything else reaches the network

    func testVideoStreamsReachTheLocalServer() {
        let transcode = origin + "/index.php/apps/memories/api/video/transcode/abc/2066890/"
        for file in ["index.m3u8", "480p.m3u8", "480p-000000.ts"] {
            XCTAssertEqual(fetch(transcode + file), .network, file)
            XCTAssertEqual(xhr(transcode + file), .network, file)
        }
    }

    func testOtherLocalPathsReachTheLocalServer() {
        for path in ["/image/preview/42?x=256&y=256", "/image/full/abc", "/video/full/42",
                     "/index.php/apps/memories/api/days", "/apps/memories/", "/local/assets/js/main.js"] {
            XCTAssertEqual(fetch(origin + path), .network, path)
            XCTAssertEqual(xhr(origin + path), .network, path)
        }
    }

    func testOtherHostsAreNotDiverted() {
        XCTAssertEqual(fetch("https://cloud.example.com/api/days"), .network)
        XCTAssertEqual(xhr("https://127.0.0.1.example.com/api/days"), .network)
    }

    // MARK: - Photo viewer full screen (issue #13)

    /// The app extends the WebView over the safe areas while the web photo viewer is open:
    /// `nativex.js` watches `.memories-viewer` entering/leaving the DOM and tells the app.
    func testViewerFullscreenFollowsTheViewerDom() {
        // Simulate DOM ready: the observer is installed (document.body exists).
        context.evaluateScript("document.body = {}; domReady.forEach((f) => f())")
        XCTAssertEqual(context.evaluateScript("observerCallbacks.length").toInt32(), 1)

        // The viewer opens: full screen on.
        context.evaluateScript("""
            posted = [];
            document.querySelector = (s) => (s === '.memories-viewer' ? {} : null);
            observerCallbacks.forEach((cb) => cb());
            """)
        XCTAssertEqual(
            context.evaluateScript("JSON.stringify(posted)").toString(),
            #"[{"method":"setViewerFullscreen","args":[true]}]"#
        )

        // No duplicate message while the viewer stays open.
        context.evaluateScript("posted = []; observerCallbacks.forEach((cb) => cb())")
        XCTAssertEqual(context.evaluateScript("posted.length").toInt32(), 0)

        // The viewer closes: full screen off.
        context.evaluateScript("""
            document.querySelector = () => null;
            observerCallbacks.forEach((cb) => cb());
            """)
        XCTAssertEqual(
            context.evaluateScript("JSON.stringify(posted)").toString(),
            #"[{"method":"setViewerFullscreen","args":[false]}]"#
        )
    }

    // MARK: - Helpers

    private enum Route: Equatable { case bridge, network, none }

    private func fetch(_ url: String) -> Route {
        route { context.evaluateScript("fetch(\(literal(url)))") }
    }

    private func xhr(_ url: String) -> Route {
        route { context.evaluateScript("(() => { const x = new XMLHttpRequest(); x.open('GET', \(literal(url))); x.send(); })()") }
    }

    /// Where the request went (the bridge message is posted synchronously).
    private func route(_ request: () -> Void) -> Route {
        context.evaluateScript("bridged = []; fetched = []; opened = [];")
        request()
        let bridged = context.evaluateScript("bridged.length").toInt32()
        let network = context.evaluateScript("fetched.length + opened.length").toInt32()
        switch (bridged, network) {
        case (1, 0): return .bridge
        case (0, 1): return .network
        default: return .none
        }
    }

    private func literal(_ string: String) -> String {
        let data = try! JSONSerialization.data(withJSONObject: [string])
        return String(data: data, encoding: .utf8)!.dropFirst().dropLast().description
    }
}
