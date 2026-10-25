import Foundation

/// Checks the URLs a server hands out during Login Flow v2 (`api/describe` is unauthenticated,
/// so its answer is not trusted blindly): the app password is sent to the host they designate,
/// and `SFSafariViewController(url:)` raises an exception for anything but http(s).
enum LoginURLPolicy {
    /// The canonical Memories root announced by the server (`baseUrl`) replaces the entered one
    /// only if it stays on the same host and does not downgrade https to http; `nil` otherwise.
    static func canonicalServer(baseUrl: String, entered: ServerURL) -> ServerURL? {
        guard let canonical = ServerURL(memoriesBaseURL: baseUrl),
              isAcceptable(canonical.memoriesURL, for: entered)
        else { return nil }
        return canonical
    }

    /// http(s) URL on the server's host (no downgrade from https).
    static func isAcceptable(_ url: URL, for server: ServerURL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host?.lowercased(), host == server.origin.host?.lowercased()
        else { return false }
        return !(server.origin.scheme?.lowercased() == "https" && scheme != "https")
    }
}
