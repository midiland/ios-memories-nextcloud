import Foundation

/// HTTP request received by the local server.
struct HTTPRequest {
    let method: String
    /// Raw target (`/path?query`), not decoded: routing is done by prefix.
    let target: String
    let version: String
    /// Headers, with lowercased names (multiple values joined with `, `).
    let headers: [String: String]
    let body: Data

    var path: String { String(target.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)[0]) }

    func header(_ name: String) -> String? { headers[name.lowercased()] }

    /// Cookies sent by the WebView.
    var cookies: [String: String] {
        var result: [String: String] = [:]
        for pair in (header("cookie") ?? "").split(separator: ";") {
            let parts = pair.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2 { result[parts[0]] = parts[1] }
        }
        return result
    }

    /// Does the client expect an HTML document (page navigation)?
    var wantsDocument: Bool {
        header("accept")?.contains("text/html") == true || header("sec-fetch-dest") == "document"
    }

    /// Whether to keep the connection open after the response (default for HTTP/1.1).
    var keepAlive: Bool {
        let connection = header("connection")?.lowercased() ?? ""
        return version == "HTTP/1.1" ? connection != "close" : connection == "keep-alive"
    }
}

/// Destination of a response body sent in pieces.
protocol HTTPBodyWriter: AnyObject {
    func write(_ data: Data) async throws
}

/// HTTP response from the local server.
struct HTTPResponse {
    enum Body {
        case empty
        case data(Data)
        /// Streamed body; nil `length` ⇒ `Transfer-Encoding: chunked`.
        case stream(length: Int?, (HTTPBodyWriter) async throws -> Void)
    }

    var status: Int
    var headers: [(String, String)] = []
    var body: Body = .empty

    static func text(_ status: Int, _ text: String) -> HTTPResponse {
        HTTPResponse(
            status: status,
            headers: [("Content-Type", "text/plain; charset=utf-8")],
            body: .data(Data(text.utf8))
        )
    }

    static let notFound = text(404, "not found")
    static let forbidden = text(403, "forbidden")

    /// Reason phrase for the status code (purely informational for HTTP/1.1 clients).
    static func reason(_ status: Int) -> String {
        let known: [Int: String] = [
            200: "OK", 201: "Created", 204: "No Content", 206: "Partial Content", 207: "Multi-Status",
            301: "Moved Permanently", 302: "Found", 304: "Not Modified",
            400: "Bad Request", 401: "Unauthorized", 403: "Forbidden", 404: "Not Found",
            411: "Length Required", 413: "Payload Too Large", 431: "Request Header Fields Too Large",
            500: "Internal Server Error", 502: "Bad Gateway", 503: "Service Unavailable", 504: "Gateway Timeout",
        ]
        return known[status] ?? "Status"
    }
}
