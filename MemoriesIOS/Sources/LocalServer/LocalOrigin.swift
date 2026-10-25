import Foundation

/// What counts as "the local server": `http://127.0.0.1:<port>` (or `localhost`), the port
/// included. The `local-auth` cookie is not port-isolated, so the port is what keeps another
/// loopback server (a malicious local app) from being treated like ours.
enum LocalOrigin {
    private static let hosts: Set<String> = [LocalHTTPServer.host, "localhost"]

    static func matches(scheme: String?, host: String?, port: Int?, localPort: UInt16) -> Bool {
        guard localPort != 0, scheme?.lowercased() == "http",
              let host = host?.lowercased(), hosts.contains(host)
        else { return false }
        return port == Int(localPort)
    }

    static func matches(_ url: URL, localPort: UInt16) -> Bool {
        matches(scheme: url.scheme, host: url.host, port: url.port, localPort: localPort)
    }

    /// A NativeX message is trusted only from the main frame served by the local server.
    /// Sub-frames (e.g. the OpenStreetMap iframe) must not reach the native functions.
    static func isTrustedFrame(isMainFrame: Bool, scheme: String, host: String, port: Int, localPort: UInt16) -> Bool {
        isMainFrame && matches(scheme: scheme, host: host, port: port, localPort: localPort)
    }

    /// State-changing request (not GET/HEAD/OPTIONS) coming from another site? The proxy adds
    /// `OCS-APIREQUEST`, which turns off Nextcloud's own CSRF protection, so the local server
    /// must check. `Sec-Fetch-Site` when the browser sends it, otherwise `Origin`; a request
    /// with neither is not from a browser page (it would still need the cookie).
    static func isCrossSiteMutation(method: String, headers: [String: String], localPort: UInt16) -> Bool {
        guard !["GET", "HEAD", "OPTIONS"].contains(method.uppercased()) else { return false }
        if let site = headers["sec-fetch-site"] {
            return site != "same-origin" && site != "none"
        }
        if let origin = headers["origin"] {
            guard let url = URL(string: origin) else { return true }
            return !matches(url, localPort: localPort)
        }
        return false
    }
}
