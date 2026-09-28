import Foundation

/// When to show the native back button.
///
/// In native mode, the frontend hides its navigation bar outside the main tabs
/// (`showNavigation` in `App.vue`) and relies on Android's back button to leave
/// pages such as "On this day", Favorites, Videos, Map or Folders. iOS has no system
/// back button, so we show our own on those pages only.
enum BackNavigationRule {
    /// App routes (after `…/apps/memories`) where the navigation bar is visible.
    private static let mainRoutes: Set<String> = ["", "/explore", "/albums"]

    static func showsBackButton(url: URL?, canGoBack: Bool, webRoot: String) -> Bool {
        guard canGoBack, let url else { return false }
        // Fragment = viewer, sidebar or open modal: they have their own close button.
        if let fragment = url.fragment, !fragment.isEmpty { return false }

        var route = url.path
        for prefix in [webRoot + "/index.php/apps/memories", webRoot + "/apps/memories"] where route.hasPrefix(prefix) {
            route.removeFirst(prefix.count)
            break
        }
        while route.hasSuffix("/") { route.removeLast() }

        // Everywhere else, including person/place/tag/album details: the web back arrows of
        // those headers are hidden by nativex.js so the app has one consistent back button.
        return !mainRoutes.contains(route)
    }
}
