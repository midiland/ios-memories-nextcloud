import Foundation

/// Configuration de l'app servie localement : serveur amont + snapshot courant.
struct LocalAppConfig {
    let credentials: Credentials
    let snapshot: Snapshot
    /// Identifiant affiché par le frontend (`<head data-user>`).
    let user: String?

    var server: ServerURL { credentials.server }
    var webRoot: String { server.webRoot }
}

/// Aiguillage des requêtes du serveur local (port de `ServerRouter.kt`). L'ordre compte :
/// 1. contrôle d'accès (hôte + cookie `local-auth`) ;
/// 2. `/api`, `/image`, `/video` : pont NativeX (normalement intercepté en JS avant d'arriver ici) ;
/// 3. `/local/static/*` (fichiers de l'app) et `/local/assets/{js,css}/*` (snapshot) ;
/// 4. chunks JS de Memories demandés par webpack → snapshot ;
/// 5. page d'entrée et routes de l'app (HTML) → page locale ;
/// 6. toute autre navigation de document → 404 (jamais de HTML distant rendu en local) ;
/// 7. le reste → relais vers Nextcloud avec les identifiants.
final class LocalRouter: @unchecked Sendable {
    private let lock = NSLock()
    private var _config: LocalAppConfig?
    private var _port: UInt16 = 0
    private let secret: String
    private let proxy = UpstreamProxy()

    init(secret: String) {
        self.secret = secret
    }

    /// App servie ; `nil` tant qu'aucun snapshot n'est prêt (ou après déconnexion).
    var config: LocalAppConfig? {
        get { lock.withLock { _config } }
        set { lock.withLock { _config = newValue } }
    }

    var port: UInt16 {
        get { lock.withLock { _port } }
        set { lock.withLock { _port = newValue } }
    }

    // MARK: - Routage

    func handle(_ request: HTTPRequest) async -> HTTPResponse {
        guard isAuthorized(request) else { return .forbidden }
        let path = request.path

        if hasPrefix(path, "/api") || hasPrefix(path, "/image") || hasPrefix(path, "/video") {
            return .notFound // pont servi par nativex.js (interception fetch/XHR)
        }
        if path.hasPrefix("/local/static/") {
            return StaticFiles.bundled(request)
        }
        if hasPrefix(path, "/local") {
            if let config {
                if path.hasPrefix("/local/assets/js/") { return StaticFiles.file(request, in: config.snapshot.jsDirectory) }
                if path.hasPrefix("/local/assets/css/") { return stylesheet(request, config: config) }
            }
            return .notFound // tout /local reste sur l'appareil
        }
        if path == "/favicon.ico" { return .notFound }

        guard let config else { return .text(503, "not configured") }
        let webRoot = config.webRoot

        let isGet = request.method == "GET"
        if isGet, path.hasPrefix(webRoot + "/index.php/apps/memories/js/") || path.hasPrefix(webRoot + "/apps/memories/js/") {
            return StaticFiles.file(request, in: config.snapshot.jsDirectory)
        }

        let appPrefix = webRoot + "/index.php/apps/memories"
        let isEntry = path == "/" || path == webRoot || path == webRoot + "/"
        let isAppRoute = hasPrefix(path, appPrefix)
        if isGet, isEntry || (isAppRoute && request.header("accept")?.contains("text/html") == true) {
            return shell(config)
        }
        if isGet, request.wantsDocument {
            return .notFound
        }
        return await proxy.forward(request, config: config, localOrigin: "http://\(LocalHTTPServer.host):\(port)")
    }

    /// URL réelle du serveur pour une navigation de page vers un chemin relayé
    /// (lien externe à ouvrir dans Safari) ; `nil` pour les documents locaux.
    func browserURL(forPath path: String, query: String?) -> URL? {
        guard let config else { return nil }
        let webRoot = config.webRoot
        let localPrefixes = ["/local", "/api", "/image", "/video", webRoot + "/index.php/apps/memories", webRoot + "/apps/memories"]
        if path == "/" || path == webRoot || path == webRoot + "/" || path == "/favicon.ico" { return nil }
        if localPrefixes.contains(where: { hasPrefix(path, $0) }) { return nil }
        let suffix = query.map { "?\($0)" } ?? ""
        return URL(string: config.server.origin.absoluteString + path + suffix)
    }

    // MARK: - Privé

    /// Cookie secret + en-tête `Host` loopback (protection contre le DNS rebinding).
    private func isAuthorized(_ request: HTTPRequest) -> Bool {
        let host = request.header("host") ?? ""
        let port = self.port
        guard host == "\(LocalHTTPServer.host):\(port)" || host == "localhost:\(port)" else { return false }
        return request.cookies["local-auth"] == secret
    }

    /// `path` vaut `prefix` ou commence par `prefix/`.
    private func hasPrefix(_ path: String, _ prefix: String) -> Bool {
        path == prefix || path.hasPrefix(prefix + "/")
    }

    /// Feuille de style du snapshot, chemins relatifs réécrits d'après son `href` d'origine.
    private func stylesheet(_ request: HTTPRequest, config: LocalAppConfig) -> HTTPResponse {
        let name = request.path.split(separator: "/").last.map(String.init) ?? ""
        guard let asset = config.snapshot.manifest.css.first(where: { $0.name == name }) else { return .notFound }
        return StaticFiles.file(request, in: config.snapshot.cssDirectory, transform: (
            version: CSSPathRewriter.version,
            apply: { CSSPathRewriter.rewrite($0, originalHref: asset.href) }
        ))
    }

    private func shell(_ config: LocalAppConfig) -> HTTPResponse {
        let nonce = UUID().uuidString
        let html = ShellPage.html(manifest: config.snapshot.manifest, webRoot: config.webRoot, user: config.user, nonce: nonce)
        return HTTPResponse(
            status: 200,
            headers: [
                ("Content-Type", "text/html; charset=utf-8"),
                ("Content-Security-Policy", ShellPage.csp(nonce: nonce)),
                ("Cache-Control", "no-store"),
            ],
            body: .data(Data(html.utf8))
        )
    }
}
