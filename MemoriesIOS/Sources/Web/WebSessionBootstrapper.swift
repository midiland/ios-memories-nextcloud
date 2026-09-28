import Foundation
import WebKit

/// Authentifie la WebView auprès de Nextcloud.
///
/// Android envoie `Authorization: Basic` sur chaque requête via son proxy local.
/// WKWebView ne permet pas d'ajouter un header aux sous-requêtes, donc on procède ainsi :
/// 1. requête `api/describe` en Basic auth via `URLSession` → Nextcloud ouvre une session
///    et renvoie ses cookies (`nc_session_id`, `oc_sessionPassphrase`, `__Host-nc_sameSiteCookie*`…) ;
/// 2. copie de ces cookies dans le `WKHTTPCookieStore` de la WebView ;
/// 3. la WebView charge la page Memories, déjà authentifiée par cookie.
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
