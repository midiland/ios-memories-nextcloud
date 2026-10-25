import Foundation

/// Which URLs the app agrees to download on behalf of the web page. The page is not fully
/// trusted (a compromised sub-frame or injected content could ask for anything): `file://`
/// would read the sandbox, and a foreign host would turn the app into an open fetcher.
enum DownloadURLPolicy {
    /// http(s) URLs on the account's server origin, or on the local server (same port).
    static func isAllowed(_ url: URL, serverOrigin: URL, local: LocalServerAccess?) -> Bool {
        if let local, local.covers(url) { return true }
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              scheme == serverOrigin.scheme?.lowercased(),
              let host = url.host?.lowercased(), host == serverOrigin.host?.lowercased(),
              url.user == nil, url.password == nil
        else { return false }
        return (url.port ?? defaultPort(scheme)) == (serverOrigin.port ?? defaultPort(scheme))
    }

    private static func defaultPort(_ scheme: String) -> Int { scheme == "https" ? 443 : 80 }
}
