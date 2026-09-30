import Foundation

/// What the web view does with a main-frame navigation (applied by `WebNavigationHandler`):
/// - local mode: only local-server pages stay in the web view; a proxied path
///   (e.g. a link to another Nextcloud app) opens the real server page in Safari;
/// - remote mode: only the account's host stays in the web view; its login page
///   means the session has expired.
struct NavigationPolicy {
    enum Mode {
        case local
        case remote
    }

    enum Decision: Equatable {
        case allow
        case external(URL)
        case sessionLost
    }

    let mode: Mode
    /// Host of the Nextcloud server (remote mode).
    let serverHost: String
    /// Whether a URL is served by the local server (local mode).
    let isLocal: (URL) -> Bool
    /// Real server page for a proxied local path, `nil` for the app's own pages (local mode).
    let serverPage: (URL) -> URL?

    func decide(_ url: URL) -> Decision {
        switch mode {
        case .local:
            guard isLocal(url) else { return .external(url) }
            if let real = serverPage(url) { return .external(real) }
            return .allow
        case .remote:
            guard url.host == serverHost else { return .external(url) }
            return Self.isLoginPage(url) ? .sessionLost : .allow
        }
    }

    /// Nextcloud web login page (`/login`, `/index.php/login`), excluding Login Flow v2.
    static func isLoginPage(_ url: URL) -> Bool {
        let components = url.pathComponents
        guard let index = components.firstIndex(of: "login") else { return false }
        let rest = components[(index + 1)...]
        return rest.isEmpty || rest.first == "challenge" || rest.first == "selectchallenge"
    }
}
