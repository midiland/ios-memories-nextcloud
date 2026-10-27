import Foundation
import WebKit

/// Clears what an ended session leaves outside the Keychain (logout or revoked credentials):
/// web view data, the locally served app, the relay's Nextcloud session cookies and the
/// manifest rollback pins (`ManifestPin`) and the widget's memories (personal photos).
/// Offline snapshots stay on disk.
@MainActor
struct SessionTeardown {
    let server: LocalHTTPServer

    func run() {
        WKWebsiteDataStore.default().removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast
        ) {}
        server.router.config = nil
        HTTPCookieStorage.shared.removeCookies(since: .distantPast)
        ManifestPinStore().removeAll()
        MemoryCache().removeAll()
    }
}
