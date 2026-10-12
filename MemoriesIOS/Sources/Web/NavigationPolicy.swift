import Foundation

/// What the web view does with a main-frame navigation (applied by `WebNavigationHandler`):
/// only local-server pages stay in the web view; a proxied path (e.g. a link to another
/// Nextcloud app) opens the real server page in Safari, and other hosts open in Safari too.
/// Pages are never loaded from the server itself: its code is untrusted (see `OfflineAppLoader`).
struct NavigationPolicy {
    enum Decision: Equatable {
        case allow
        case external(URL)
    }

    /// Whether a URL is served by the local server.
    let isLocal: (URL) -> Bool
    /// Real server page for a proxied local path, `nil` for the app's own pages.
    let serverPage: (URL) -> URL?

    func decide(_ url: URL) -> Decision {
        guard isLocal(url) else { return .external(url) }
        if let real = serverPage(url) { return .external(real) }
        return .allow
    }
}
