import Foundation

/// Requête HTTP reçue par le serveur local.
struct HTTPRequest {
    let method: String
    /// Cible brute (`/chemin?requête`), non décodée : le routage se fait par préfixe.
    let target: String
    let version: String
    /// En-têtes, noms en minuscules (valeurs multiples jointes par `, `).
    let headers: [String: String]
    let body: Data

    var path: String { String(target.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)[0]) }

    func header(_ name: String) -> String? { headers[name.lowercased()] }

    /// Cookies envoyés par la WebView.
    var cookies: [String: String] {
        var result: [String: String] = [:]
        for pair in (header("cookie") ?? "").split(separator: ";") {
            let parts = pair.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2 { result[parts[0]] = parts[1] }
        }
        return result
    }

    /// Le client attend-il un document HTML (navigation de page) ?
    var wantsDocument: Bool {
        header("accept")?.contains("text/html") == true || header("sec-fetch-dest") == "document"
    }

    /// Connexion à garder ouverte après la réponse (HTTP/1.1 par défaut).
    var keepAlive: Bool {
        let connection = header("connection")?.lowercased() ?? ""
        return version == "HTTP/1.1" ? connection != "close" : connection == "keep-alive"
    }
}

/// Destination d'un corps de réponse envoyé par morceaux.
protocol HTTPBodyWriter: AnyObject {
    func write(_ data: Data) async throws
}

/// Réponse HTTP du serveur local.
struct HTTPResponse {
    enum Body {
        case empty
        case data(Data)
        /// Corps diffusé en continu ; `length` nil ⇒ `Transfer-Encoding: chunked`.
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

    /// Libellé du code de statut (purement informatif pour les clients HTTP/1.1).
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
