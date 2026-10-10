import WebKit

/// Navigation and UI delegate for the web view (equivalent of `MemoriesWebViewClient`
/// and `MemoriesWebChromeClient` on Android).
///
/// - main-frame navigations follow `NavigationPolicy` (app pages stay, the rest opens in Safari,
///   remote login page = expired session → re-bootstrap);
/// - network / HTTP errors on the main document → error screen.
@MainActor
final class WebNavigationHandler: NSObject, WKNavigationDelegate, WKUIDelegate {
    weak var model: WebViewModel?

    // MARK: - Navigation policy

    func webView(
        _ webView: WKWebView,
        decidePolicyFor action: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = action.request.url, let model else { return decisionHandler(.allow) }

        // Subframes (OpenStreetMap map, previews…) are not filtered.
        let isMainFrame = action.targetFrame?.isMainFrame ?? true
        guard isMainFrame else { return decisionHandler(.allow) }

        switch url.scheme?.lowercased() {
        case "about", "blob", "data":
            return decisionHandler(.allow)
        case "http", "https":
            break
        default:
            // mailto:, tel:, etc.
            model.openExternally(url)
            return decisionHandler(.cancel)
        }

        switch model.navigationPolicy.decide(url) {
        case .allow:
            decisionHandler(.allow)
        case .external(let target):
            decisionHandler(.cancel)
            model.openExternally(target)
        case .sessionLost:
            decisionHandler(.cancel)
            model.sessionLost()
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor response: WKNavigationResponse,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void
    ) {
        guard response.isForMainFrame, let http = response.response as? HTTPURLResponse else {
            return decisionHandler(.allow)
        }
        switch http.statusCode {
        case 401:
            decisionHandler(.cancel)
            model?.sessionLost()
        case 404 where model?.mode == .remote:
            decisionHandler(.cancel)
            model?.pageDidFail(.memoriesNotInstalled)
        case 400...:
            decisionHandler(.cancel)
            model?.pageDidFail(.unexpectedStatus(http.statusCode))
        default:
            decisionHandler(.allow)
        }
    }

    // MARK: - Load lifecycle

    /// First render of the document: remove the native overlay without waiting for the load to finish
    /// (the frontend shows its own indicators; in local mode the page arrives in ~50 ms).
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        model?.pageDidFinish()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handle(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handle(error)
    }

    /// The WebContent process was killed (memory pressure): reload once possible.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        model?.webContentProcessDidTerminate()
    }

    // MARK: - UI

    /// `target=_blank` / `window.open`: same rule as main-frame navigation.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for action: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard let url = action.request.url, let model else { return nil }
        switch model.navigationPolicy.decide(url) {
        case .allow: webView.load(action.request)
        case .external(let target): model.openExternally(target)
        case .sessionLost: model.sessionLost()
        }
        return nil
    }

    // MARK: - Private

    private func handle(_ error: Error) {
        let nsError = error as NSError
        // Navigation cancelled (by us or by a new load): not a real error.
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled { return }
        if nsError.domain == "WebKitErrorDomain" && nsError.code == 102 { return } // interrupted by policy
        Log.web.error("Page load failed: \(String(describing: error), privacy: .public)")
        model?.pageDidFail(loading: error)
    }
}
