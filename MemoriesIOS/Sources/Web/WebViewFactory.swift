import UIKit
import WebKit

/// Creates and configures the `WKWebView` (equivalent of `WebViewSetup.kt` on Android).
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
        // Transparent background while loading (no white flash in dark mode).
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear

        #if DEBUG
        // Inspect via Safari > Develop (iOS 16.4+).
        if #available(iOS 16.4, *) { webView.isInspectable = true }
        #endif
        return webView
    }

    /// User-Agent suffix. It must look like mobile Safari, otherwise Nextcloud may
    /// show its "unsupported browser" page before `nativex.initialize()`
    /// (frontend) has disabled that check.
    private static var userAgentApplicationName: String {
        let parts = UIDevice.current.systemVersion.split(separator: ".").prefix(2)
        let version = parts.count == 2 ? parts.joined(separator: ".") : "\(parts.first ?? "16").0"
        return "Version/\(version) Mobile/15E148 Safari/604.1 \(AppConstants.userAgentSuffix)"
    }
}
