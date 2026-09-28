import WebKit

/// `WKUserContentController` retient fortement ses handlers : ce proxy à référence
/// faible évite le cycle WebView → configuration → handler → modèle → WebView.
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
        guard let target else { return replyHandler(nil, "NativeX indisponible") }
        target.userContentController(controller, didReceive: message, replyHandler: replyHandler)
    }
}
