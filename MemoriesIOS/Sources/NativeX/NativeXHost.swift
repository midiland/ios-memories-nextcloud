import UIKit

/// What the NativeX bridge asks of the host app (implemented by `WebViewModel`).
/// The bridge decodes JS messages; the host acts on the UI and the session.
@MainActor
protocol NativeXHost: AnyObject {
    /// Web UI theme color (`nil` = system color), and whether it is dark.
    func nativeXSetTheme(color: UIColor?, isDark: Bool)

    /// Short message shown over the WebView.
    func nativeXToast(_ message: String, long: Bool)

    /// Logout requested from Settings > Account in the web UI.
    func nativeXLogout()

    /// Full reload (session re-bootstrap + Memories page).
    func nativeXReload()

    /// Runs a script in the page (state updates, events on the frontend's bus).
    func nativeXEvaluate(_ script: String)
}
