import UIKit
import WebKit

/// Crée et configure la `WKWebView` (équivalent de `WebViewSetup.kt` sur Android).
@MainActor
enum WebViewFactory {
    static func make(bridge: NativeXBridge) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.applicationNameForUserAgent = userAgentApplicationName
        bridge.install(into: config.userContentController)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsLinkPreview = false
        // Fond transparent pendant le chargement (pas de flash blanc en mode sombre).
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear

        #if DEBUG
        // Inspection via Safari > Développement (iOS 16.4+).
        if #available(iOS 16.4, *) { webView.isInspectable = true }
        #endif
        return webView
    }

    /// Suffixe du User-Agent. Il doit ressembler à Safari mobile, sinon Nextcloud affiche
    /// sa page « navigateur non supporté » (sur Android, c'est `nativex.initialize()` qui la
    /// désactive, ce qu'on ne peut pas encore faire sans pont NativeX).
    private static var userAgentApplicationName: String {
        let parts = UIDevice.current.systemVersion.split(separator: ".").prefix(2)
        let version = parts.count == 2 ? parts.joined(separator: ".") : "\(parts.first ?? "16").0"
        return "Version/\(version) Mobile/15E148 Safari/604.1 \(AppConstants.userAgentSuffix)"
    }
}
