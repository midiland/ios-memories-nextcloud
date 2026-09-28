import WebKit

/// Délégué de navigation et d'UI de la WebView (équivalent de `MemoriesWebViewClient`
/// et `MemoriesWebChromeClient` sur Android).
///
/// Règles (détaillées dans `WebViewModel.decideNavigation`) :
/// - seules les pages de l'app restent dans la WebView, le reste part dans Safari ;
/// - mode distant : une redirection vers la page de login Nextcloud = session expirée → réamorçage ;
/// - erreurs réseau / HTTP du document principal → écran d'erreur.
@MainActor
final class WebNavigationHandler: NSObject, WKNavigationDelegate, WKUIDelegate {
    enum Decision {
        case allow
        case external(URL)
        case sessionLost
    }

    weak var model: WebViewModel?

    // MARK: - Politique de navigation

    func webView(
        _ webView: WKWebView,
        decidePolicyFor action: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = action.request.url, let model else { return decisionHandler(.allow) }

        // Les sous-frames (carte OpenStreetMap, aperçus…) ne sont pas filtrés.
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

        switch model.decideNavigation(to: url) {
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

    // MARK: - Cycle de chargement

    /// Premier rendu du document : on retire le voile natif sans attendre la fin du chargement
    /// (le frontend affiche ses propres indicateurs ; en mode local la page arrive en ~50 ms).
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        model?.pageDidFinish()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handle(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handle(error)
    }

    /// Le processus WebContent a été tué (mémoire) : on recharge.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }

    // MARK: - UI

    /// `target=_blank` / `window.open` : même règle que la navigation principale.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for action: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard let url = action.request.url, let model else { return nil }
        switch model.decideNavigation(to: url) {
        case .allow: webView.load(action.request)
        case .external(let target): model.openExternally(target)
        case .sessionLost: model.sessionLost()
        }
        return nil
    }

    // MARK: - Privé

    private func handle(_ error: Error) {
        let nsError = error as NSError
        // Navigation annulée (par nous ou par un nouveau chargement) : pas une vraie erreur.
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled { return }
        if nsError.domain == "WebKitErrorDomain" && nsError.code == 102 { return } // interrompu par la politique
        model?.pageDidFail(.serverUnreachable(error.localizedDescription))
    }

    /// Page de login web de Nextcloud (`/login`, `/index.php/login`), hors Login Flow v2.
    static func isLoginPage(_ url: URL) -> Bool {
        let components = url.pathComponents
        guard let index = components.firstIndex(of: "login") else { return false }
        let rest = components[(index + 1)...]
        return rest.isEmpty || rest.first == "challenge" || rest.first == "selectchallenge"
    }
}
