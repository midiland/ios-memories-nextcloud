import Foundation

/// What a native request needs to go through the app's own local server: its port and the
/// `local-auth` secret. The frontend builds download URLs on the page origin
/// (`http://127.0.0.1:<port>/…`, `addOrigin` in `src/native/basic.ts`), and the local server
/// refuses requests without the cookie (403), like `InAppDownloader.kt` on Android, which reads it
/// from the web view's cookie manager.
struct LocalServerAccess: Equatable {
    let port: UInt16
    let secret: String

    /// Whether `url` targets this local server (loopback host and same port). The secret is never
    /// sent anywhere else: another app could listen on another loopback port.
    func covers(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "http", let host = url.host?.lowercased() else { return false }
        return (host == LocalHTTPServer.host || host == "localhost") && url.port == Int(port)
    }
}
