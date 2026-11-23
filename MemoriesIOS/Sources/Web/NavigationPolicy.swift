import Foundation

/// What the web view does with a main-frame navigation (applied by `WebNavigationHandler`):
/// only local-server pages stay in the web view; a proxied path (e.g. a link to another
/// Nextcloud app) opens the real server page in Safari, and other hosts open in Safari too.
/// Pages are never loaded from the server itself: its code is untrusted (see `OfflineAppLoader`).
/// Store links that servers without `getPlatform` support still hardcode for Android are swapped
/// for their App Store equivalent (newer frontends pick the App Store link themselves).
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
        guard isLocal(url) else { return .external(Self.appStoreEquivalent(of: url) ?? url) }
        if let real = serverPage(url) { return .external(real) }
        return .allow
    }

    /// Google Play app ids linked by the frontend → App Store page of the iOS app.
    /// The native setup screen points "Set up automatic upload" to the Android Nextcloud app.
    private static let appStorePages: [String: URL] = [
        "com.nextcloud.client": URL(string: "https://apps.apple.com/app/nextcloud/id1125420102")!,
    ]

    private static func appStoreEquivalent(of url: URL) -> URL? {
        guard url.host?.lowercased() == "play.google.com", url.path == "/store/apps/details",
              let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                  .queryItems?.first(where: { $0.name == "id" })?.value
        else { return nil }
        return appStorePages[id]
    }
}
