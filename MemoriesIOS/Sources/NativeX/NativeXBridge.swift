import WebKit

/// Pont NativeX : expose des fonctions natives au JavaScript de Memories.
///
/// Sur Android c'est l'objet `window.nativex` (`addJavascriptInterface`) plus un pont HTTP
/// sur 127.0.0.1 (voir docs/ANALYSE.md §3). Sur iOS, l'implémentation prévue :
/// - un `WKUserScript` injecté en `.atDocumentStart` qui définit `window.nativex`
///   (le frontend le lit dès le chargement de ses modules) ;
/// - un `WKScriptMessageHandler` nommé `nativex` qui reçoit `{ method, args }` ;
/// - un cache JS pour les méthodes synchrones (voir `NativeXMethod.isSynchronous`).
///
/// ⚠️ Tant que le pont n'est pas complet, il ne doit PAS définir `window.nativex` :
/// le frontend basculerait en mode natif et appellerait `http://127.0.0.1`.
@MainActor
protocol NativeXBridge: AnyObject {
    /// Installe scripts et handlers dans la configuration de la WebView.
    func install(into controller: WKUserContentController)

    /// Retire scripts et handlers.
    /// Note : `WKUserContentController` retient fortement ses message handlers ;
    /// l'implémentation devra passer par un proxy à référence faible pour éviter un cycle.
    func uninstall(from controller: WKUserContentController)
}

/// Implémentation vide utilisée par le MVP : aucune fonction native n'est exposée.
final class DisabledNativeXBridge: NativeXBridge {
    func install(into controller: WKUserContentController) {}
    func uninstall(from controller: WKUserContentController) {}
}
