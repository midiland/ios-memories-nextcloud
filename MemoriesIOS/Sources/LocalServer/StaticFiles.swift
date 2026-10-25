import Foundation

/// Locally served files (port of `StaticController.kt`). Lookup by file name only
/// (last path segment, percent-decoded then validated): no directory traversal possible.
enum StaticFiles {
    /// File bundled in the app (`Resources/`), e.g. `shell-overrides.css`.
    static func bundled(_ request: HTTPRequest) -> HTTPResponse {
        guard let name = fileName(request) else { return .notFound }
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        guard let url = Bundle.main.url(forResource: base, withExtension: ext),
              let data = try? Data(contentsOf: url)
        else { return .notFound }
        return HTTPResponse(
            status: 200,
            headers: [("Content-Type", mimeType(ext)), ("Cache-Control", "no-store")],
            body: .data(data)
        )
    }

    /// Snapshot file, validated by ETag so WebKit reuses its cache.
    /// Optional `transform` applied to the content (its `version` is part of the ETag).
    static func file(
        _ request: HTTPRequest, in directory: URL,
        transform: (version: String, apply: (Data) -> Data)? = nil
    ) -> HTTPResponse {
        guard let name = fileName(request) else { return .notFound }
        let url = directory.appendingPathComponent(name)
        // Defence in depth: the resolved file must stay directly inside `directory`.
        guard url.standardizedFileURL.deletingLastPathComponent().path == directory.standardizedFileURL.path,
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? Int
        else { return .notFound }

        let modified = Int((attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)
        let suffix = transform.map { "-\($0.version)" } ?? ""
        let etag = "\"\(String(modified, radix: 16))-\(String(size, radix: 16))\(suffix)\""
        var headers = [("ETag", etag), ("Cache-Control", "no-cache")]

        let candidates = (request.header("if-none-match") ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        if candidates.contains(etag) || candidates.contains("*") {
            return HTTPResponse(status: 304, headers: headers)
        }
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return .notFound }
        headers.append(("Content-Type", mimeType(url.pathExtension)))
        return HTTPResponse(status: 200, headers: headers, body: .data(transform?.apply(data) ?? data))
    }

    /// Requested file name; `nil` (→ 404) if empty, suspicious, or the method is not GET/HEAD.
    private static func fileName(_ request: HTTPRequest) -> String? {
        guard request.method == "GET" || request.method == "HEAD" else { return nil }
        guard let segment = request.path.split(separator: "/").last.map(String.init),
              let name = segment.removingPercentEncoding,
              isSafeName(name)
        else { return nil }
        return name
    }

    /// A plain file name, checked AFTER percent-decoding (`%2e%2e%2f` must not slip through):
    /// no separator, no `..`, no control character (NUL included).
    static func isSafeName(_ name: String) -> Bool {
        !name.isEmpty
            && !name.contains("/") && !name.contains("\\") && !name.contains("..")
            && !name.unicodeScalars.contains { $0.value < 0x20 || $0.value == 0x7f }
    }

    private static func mimeType(_ ext: String) -> String {
        switch ext.lowercased() {
        case "js", "mjs": return "text/javascript; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "html": return "text/html; charset=utf-8"
        case "svg": return "image/svg+xml"
        case "png": return "image/png"
        case "json": return "application/json"
        case "map": return "application/json"
        default: return "application/octet-stream"
        }
    }
}
