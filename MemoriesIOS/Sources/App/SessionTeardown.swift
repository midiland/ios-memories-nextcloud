import Foundation

/// Clears what an ended session leaves outside the Keychain (logout or revoked credentials):
/// web view data, the locally served app and the relay's Nextcloud session cookies.
/// Offline snapshots stay on disk.
@MainActor
struct SessionTeardown {
    let server: LocalHTTPServer

    func run() {
        WebSessionBootstrapper.clearWebsiteData()
        server.router.config = nil
        HTTPCookieStorage.shared.removeCookies(since: .distantPast)
    }
}
