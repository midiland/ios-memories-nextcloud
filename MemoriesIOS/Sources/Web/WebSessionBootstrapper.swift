import Foundation
import WebKit

/// Authentifie la WebView auprès de Nextcloud.
///
/// Android envoie `Authorization: Basic` sur chaque requête via son proxy local.
/// WKWebView ne permet pas d'ajouter un header aux sous-requêtes, donc on procède ainsi :
/// 1. requête `api/describe` en Basic auth via `URLSession` → Nextcloud ouvre une session
///    et renvoie ses cookies (`nc_session_id`, `oc_sessionPassphrase`, `__Host-nc_sameSiteCookie*`…) ;
/// 2. copie de ces cookies dans le `WKHTTPCookieStore` de la WebView ;
/// 3. ajout du cookie `nx_auth` = header Basic : en mode natif (User-Agent `MemoriesNative`),
///    le serveur le traduit en `Authorization` sur chaque requête
///    (`Application::handleNativeHeaders`), ce qui survit à l'expiration de la session ;
/// 4. la WebView charge la page Memories, déjà authentifiée.
@MainActor
enum WebSessionBootstrapper {
    /// Vérifie les identifiants et installe les cookies de session dans la WebView.
    /// Lève `AppError.notAuthenticated` si le serveur refuse les identifiants.
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

    /// Cookie `nx_auth` (HttpOnly, invisible du JS). La valeur est encodée en pourcentage :
    /// PHP décode automatiquement `$_COOKIE`, ce qui redonne `Basic <base64>`.
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

    /// Efface cookies, cache et stockage local de la WebView (déconnexion).
    static func clearWebsiteData() {
        let store = WKWebsiteDataStore.default()
        store.removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: .distantPast
        ) {}
    }
}
