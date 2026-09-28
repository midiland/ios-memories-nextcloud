import WebKit

/// NativeX bridge: exposes native functions to the Memories JavaScript.
///
/// On Android this is the `window.nativex` object (`addJavascriptInterface`) plus an HTTP bridge
/// on 127.0.0.1 (see docs/ANALYSE.md §3). iOS implementation: `NativeXController`.
@MainActor
protocol NativeXBridge: AnyObject {
    /// Installs scripts and handlers into the WebView configuration.
    func install(into controller: WKUserContentController)

    /// Removes scripts and handlers.
    /// Note: `WKUserContentController` strongly retains its message handlers;
    /// the implementation must go through a weak-reference proxy to avoid a retain cycle.
    func uninstall(from controller: WKUserContentController)
}
