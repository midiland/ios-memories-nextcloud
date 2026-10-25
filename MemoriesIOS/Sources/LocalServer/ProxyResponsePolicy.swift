import Foundation

/// Header rewriting for responses relayed from Nextcloud into the local origin.
///
/// The local origin may run scripts (`script-src 'self'`, bridge, cookie), so a relayed
/// response must never be executable there: the server is untrusted for code. Executable
/// types are downgraded to `text/plain` and `nosniff` stops WebKit from guessing otherwise.
enum ProxyResponsePolicy {
    /// Headers regenerated locally (URLSession already decompresses the body).
    private static let skipped: Set<String> = [
        "content-encoding", "transfer-encoding", "content-length", "connection", "keep-alive", "set-cookie",
    ]
    /// Media types a document, script or worker could execute.
    private static let executable: Set<String> = [
        "text/javascript", "application/javascript", "application/x-javascript", "text/ecmascript",
        "application/ecmascript", "text/jscript", "text/livescript", "application/wasm",
        "text/html", "application/xhtml+xml",
    ]
    /// Markup that can embed script when opened as a document: kept, but sandboxed.
    private static let sandboxed: Set<String> = ["image/svg+xml", "text/xml", "application/xml"]

    static func mediaType(_ contentType: String) -> String {
        contentType.split(separator: ";", maxSplits: 1).first
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() } ?? ""
    }

    static func headers(
        from upstream: [(String, String)], serverOrigin: String, localOrigin: String
    ) -> [(String, String)] {
        var result: [(String, String)] = []
        var sandbox = false
        for (name, value) in upstream {
            let lower = name.lowercased()
            if skipped.contains(lower) || lower == "x-content-type-options" { continue }
            switch lower {
            case "location" where value.hasPrefix(serverOrigin):
                result.append((name, localOrigin + value.dropFirst(serverOrigin.count)))
            case "content-type":
                let type = mediaType(value)
                if executable.contains(type) {
                    result.append((name, "text/plain; charset=utf-8"))
                } else {
                    sandbox = sandboxed.contains(type)
                    result.append((name, value))
                }
            default:
                result.append((name, value))
            }
        }
        result.append(("X-Content-Type-Options", "nosniff"))
        if sandbox { result.append(("Content-Security-Policy", "sandbox")) }
        return result
    }
}
