import Foundation

/// Request routing for the local server (port of `ServerRouter.kt`). Order matters:
/// 1. access control (host + `local-auth` cookie);
/// 2. `/image/preview|full`: device photos as JPEG; other `/api`, `/image`, `/video`: NativeX bridge
///    (normally intercepted in JS before reaching here);
/// 3. `/local/static/*` (app files) and `/local/assets/{js,css}/*` (snapshot);
/// 4. Memories JS chunks requested by webpack → snapshot;
/// 5. entry page and app routes (HTML) → local page;
/// 6. any other document navigation → 404 (remote HTML is never rendered locally);
/// 7. everything else → proxied to Nextcloud with the credentials.
final class LocalRouter: @unchecked Sendable {
    private let lock = NSLock()
    private var _config: LocalAppConfig?
    private var _port: UInt16 = 0
    private let secret: String
    private let proxy = UpstreamProxy()

    init(secret: String) {
        self.secret = secret
    }

    /// Served app; `nil` until a snapshot is ready (or after logout).
    var config: LocalAppConfig? {
        get { lock.withLock { _config } }
        set { lock.withLock { _config = newValue } }
    }

    var port: UInt16 {
        get { lock.withLock { _port } }
        set { lock.withLock { _port = newValue } }
    }

    // MARK: - Routing

    func handle(_ request: HTTPRequest) async -> HTTPResponse {
        guard isAuthorized(request) else {
            // Requests not made by the page itself, e.g. a media loader without the page's cookies.
            Log.localServer.notice("Forbidden: \(request.method, privacy: .public) \(request.path, privacy: .public) (\(request.header("user-agent") ?? "no user agent", privacy: .public))")
            return .forbidden
        }
        let path = request.path

        if hasPrefix(path, "/image") {
            return await localImage(request, media: config?.media)
        }
        if hasPrefix(path, "/api") || hasPrefix(path, "/video") {
            return .notFound // bridge served by nativex.js (fetch/XHR interception)
        }
        if path.hasPrefix("/local/static/") {
            return StaticFiles.bundled(request)
        }
        if hasPrefix(path, "/local") {
            if let config {
                if path.hasPrefix("/local/assets/js/") { return StaticFiles.file(request, in: config.snapshot.jsDirectory) }
                if path.hasPrefix("/local/assets/css/") { return stylesheet(request, config: config) }
            }
            return .notFound // all of /local stays on the device
        }
        if path == "/favicon.ico" { return .notFound }

        guard let config else { return .text(503, "not configured") }
        let webRoot = config.webRoot

        let isGet = request.method == "GET"
        if isGet, config.server.appPaths.contains(where: { path.hasPrefix($0 + "/js/") }) {
            return StaticFiles.file(request, in: config.snapshot.jsDirectory)
        }

        let isEntry = path == "/" || path == webRoot || path == webRoot + "/"
        let isAppRoute = hasPrefix(path, config.server.appPath)
        if isGet, isEntry || (isAppRoute && request.header("accept")?.contains("text/html") == true) {
            return shell(config)
        }
        if isGet, request.wantsDocument {
            return .notFound
        }
        return await proxy.forward(request, config: config, localOrigin: "http://\(LocalHTTPServer.host):\(port)")
    }

    /// Real server URL for a page navigation to a proxied path
    /// (external link to open in Safari); `nil` for local documents.
    func browserURL(forPath path: String, query: String?) -> URL? {
        guard let config else { return nil }
        let webRoot = config.webRoot
        let localPrefixes = ["/local", "/api", "/image", "/video"] + config.server.appPaths
        if path == "/" || path == webRoot || path == webRoot + "/" || path == "/favicon.ico" { return nil }
        if localPrefixes.contains(where: { hasPrefix(path, $0) }) { return nil }
        let suffix = query.map { "?\($0)" } ?? ""
        return URL(string: config.server.origin.absoluteString + path + suffix)
    }

    // MARK: - Private

    /// Secret cookie + loopback `Host` header (protection against DNS rebinding).
    private func isAuthorized(_ request: HTTPRequest) -> Bool {
        let host = request.header("host") ?? ""
        let port = self.port
        guard host == "\(LocalHTTPServer.host):\(port)" || host == "localhost:\(port)" else { return false }
        return request.cookies["local-auth"] == secret
    }

    /// `path` equals `prefix` or starts with `prefix/`.
    private func hasPrefix(_ path: String, _ prefix: String) -> Bool {
        path == prefix || path.hasPrefix(prefix + "/")
    }

    /// Snapshot stylesheet, with relative paths rewritten based on its original `href`.
    private func stylesheet(_ request: HTTPRequest, config: LocalAppConfig) -> HTTPResponse {
        let name = request.path.split(separator: "/").last.map(String.init) ?? ""
        guard let asset = config.snapshot.manifest.css.first(where: { $0.name == name }) else { return .notFound }
        return StaticFiles.file(request, in: config.snapshot.cssDirectory, transform: (
            version: CSSPathRewriter.version,
            apply: { CSSPathRewriter.rewrite($0, originalHref: asset.href) }
        ))
    }

    /// `/image/preview/{fileid}?x&y` and `/image/full/{auid}?size` (`NAPI` in `src/native/api.ts`).
    private func localImage(_ request: HTTPRequest, media: LocalMediaProvider?) async -> HTTPResponse {
        guard let media, request.method == "GET" || request.method == "HEAD" else { return .notFound }
        let parts = request.path.split(separator: "/").map(String.init)
        guard parts.count == 3 else { return .notFound }
        let query = Self.queryItems(request.target)

        let data: Data?
        switch parts[1] {
        case "preview":
            guard let fileId = Int64(parts[2]) else { return .notFound }
            data = await media.preview(fileId: fileId, width: query["x"].flatMap(Int.init), height: query["y"].flatMap(Int.init))
        case "full":
            data = await media.full(auid: parts[2], longEdge: query["size"].flatMap(Int.init))
        default:
            return .notFound
        }
        guard let data else { return .notFound }
        return HTTPResponse(
            status: 200,
            headers: [("Content-Type", "image/jpeg"), ("Cache-Control", "private, max-age=3600")],
            body: .data(data)
        )
    }

    private static func queryItems(_ target: String) -> [String: String] {
        let items = URLComponents(string: target)?.queryItems ?? []
        return Dictionary(items.compactMap { item in item.value.map { (item.name, $0) } }, uniquingKeysWith: { first, _ in first })
    }

    private func shell(_ config: LocalAppConfig) -> HTTPResponse {
        let nonce = UUID().uuidString
        // `mod_rewrite_working` mirrors the upstream server's URL style (with or without
        // `index.php`), taken from the canonical `baseUrl` returned by `api/describe`.
        // The local server accepts both forms (`appPaths`), so this only affects the URLs
        // the frontend generates (e.g. public share links) — they must match the server.
        let modRewriteWorking = !config.server.memoriesURL.absoluteString.contains("index.php")
        let html = ShellPage.html(manifest: config.snapshot.manifest, webRoot: config.webRoot, user: config.user, nonce: nonce, modRewriteWorking: modRewriteWorking)
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
