import SwiftUI
import WebKit

/// Embeds the `WKWebView` owned by `WebViewModel` in SwiftUI.
///
/// The web view lives in the model (not in `makeUIView`) so it survives
/// SwiftUI view re-creation without reloading the page.
struct MemoriesWebView: UIViewRepresentable {
    let model: WebViewModel

    func makeUIView(context: Context) -> WKWebView {
        model.webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}
}
