import WebKit

/// Pont NativeX : expose des fonctions natives au JavaScript de Memories.
///
/// Sur Android c'est l'objet `window.nativex` (`addJavascriptInterface`) plus un pont HTTP
/// sur 127.0.0.1 (voir docs/ANALYSE.md §3). Implémentation iOS : `NativeXController`.
@MainActor
protocol NativeXBridge: AnyObject {
    /// Installe scripts et handlers dans la configuration de la WebView.
    func install(into controller: WKUserContentController)

    /// Retire scripts et handlers.
    /// Note : `WKUserContentController` retient fortement ses message handlers ;
    /// l'implémentation devra passer par un proxy à référence faible pour éviter un cycle.
    func uninstall(from controller: WKUserContentController)
}
