import SwiftUI
import WebKit

/// Intègre la `WKWebView` possédée par `WebViewModel` dans SwiftUI.
///
/// La WebView vit dans le modèle (et non dans `makeUIView`) pour survivre aux
/// recréations de vues SwiftUI sans recharger la page.
struct MemoriesWebView: UIViewRepresentable {
    let model: WebViewModel

    func makeUIView(context: Context) -> WKWebView {
        model.webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}
}
