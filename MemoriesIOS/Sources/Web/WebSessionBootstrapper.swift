import Foundation
import WebKit

/// Authenticates the web view with Nextcloud.
///
/// Android sends `Authorization: Basic` on every request through its local proxy.
/// WKWebView cannot add a header to subrequests, so we do the following:
/// 1. `api/describe` request with Basic auth via `URLSession` → Nextcloud opens a session
///    and returns its cookies (`nc_session_id`, `oc_sessionPassphrase`, `__Host-nc_sameSiteCookie*`…);
/// 2. copy those cookies into the web view's `WKHTTPCookieStore`;
/// 3. add the `nx_auth` cookie = Basic header: in native mode (User-Agent `MemoriesNative`),
///    the server translates it into `Authorization` on every request
///    (`Application::handleNativeHeaders`), which survives session expiry;
/// 4. the web view loads the Memories page, already authenticated.
@MainActor
enum WebSessionBootstrapper {
    /// Checks the credentials and installs the session cookies in the web view.
    /// Throws `AppError.notAuthenticated` if the server rejects the credentials.
    static func bootstrap(_ credentials: Credentials, into cookieStore: WKHTTPCookieStore) async throws {
        let client = NextcloudClient()
        let describe = try await client.describe(credentials.server, credentials: credentials)
        guard describe.uid != nil else { throw AppError.notAuthenticated }

        for cookie in client.cookies(for: credentials.server) {
            await cookieStore.setCookie(cookie)
        }
        if let authCookie = nativeAuthCookie(credentials) {
            await cookieStore.setCookie(authCookie)
        }
    }

    /// `nx_auth` cookie (HttpOnly, hidden from JS). The value is percent-encoded:
    /// PHP automatically decodes `$_COOKIE`, which yields `Basic <base64>` again.
    private static func nativeAuthCookie(_ credentials: Credentials) -> HTTPCookie? {
        let server = credentials.server
        let allowed = CharacterSet.alphanumerics
        guard let value = credentials.basicAuthHeader.addingPercentEncoding(withAllowedCharacters: allowed) else {
            return nil
        }
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: "nx_auth",
            .value: value,
            .domain: server.host,
            .path: "/",
            .expires: Date().addingTimeInterval(365 * 24 * 3600),
            HTTPCookiePropertyKey("HttpOnly"): "TRUE",
        ]
        if server.memoriesURL.scheme == "https" {
            properties[.secure] = "TRUE"
        }
        return HTTPCookie(properties: properties)
    }

    /// Clears the web view's cookies, cache and local storage (logout).
    static func clearWebsiteData() {
        let store = WKWebsiteDataStore.default()
        store.removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: .distantPast
        ) {}
    }
}
