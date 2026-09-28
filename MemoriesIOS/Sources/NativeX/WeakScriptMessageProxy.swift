import WebKit

/// `WKUserContentController` strongly retains its handlers: this weak-reference proxy
/// avoids the WebView → configuration → handler → model → WebView retain cycle.
final class WeakScriptMessageProxy: NSObject, WKScriptMessageHandler, WKScriptMessageHandlerWithReply {
    private weak var target: (WKScriptMessageHandler & WKScriptMessageHandlerWithReply)?

    init(_ target: WKScriptMessageHandler & WKScriptMessageHandlerWithReply) {
        self.target = target
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }

    func userContentController(
        _ controller: WKUserContentController,
        didReceive message: WKScriptMessage,
        replyHandler: @escaping @MainActor @Sendable (Any?, String?) -> Void
    ) {
        guard let target else { return replyHandler(nil, "NativeX unavailable") }
        target.userContentController(controller, didReceive: message, replyHandler: replyHandler)
    }
}
