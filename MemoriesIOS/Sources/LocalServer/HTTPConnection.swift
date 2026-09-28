import Foundation
import Network

/// Une connexion TCP du serveur local : analyse HTTP/1.1 minimale (en-têtes + corps
/// `Content-Length`), une requête à la fois, keep-alive, réponses complètes ou en flux.
///
/// L'état est confiné à `queue` ; le traitement de la requête se fait dans une `Task`.
final class HTTPConnection: HTTPBodyWriter, @unchecked Sendable {
    typealias Handler = @Sendable (HTTPRequest) async -> HTTPResponse

    private let connection: NWConnection
    private let queue = DispatchQueue(label: "memories.localserver.connection")
    private let handler: Handler
    private var buffer = Data()
    private var chunked = false

    /// Taille max des en-têtes et du corps d'une requête (les uploads web passent par des morceaux WebDAV).
    private let maxHeaderSize = 64 * 1024
    private let maxBodySize = 512 * 1024 * 1024

    init(_ connection: NWConnection, handler: @escaping Handler) {
        self.connection = connection
        self.handler = handler
    }

    /// Démarre la connexion. Les handlers retiennent `self` jusqu'à la fermeture
    /// (personne d'autre ne garde de référence sur la connexion).
    func start() {
        connection.stateUpdateHandler = { state in
            switch state {
            case .failed:
                self.connection.cancel()
            case .cancelled:
                self.connection.stateUpdateHandler = nil // rompt le cycle de rétention
            default:
                break
            }
        }
        connection.start(queue: queue)
        receive()
    }

    // MARK: - Lecture

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { data, _, isComplete, error in
            if let data { self.buffer.append(data) }
            if error != nil { return self.connection.cancel() }
            if self.tryHandleRequest() { return }
            if isComplete { return self.connection.cancel() }
            self.receive()
        }
    }

    /// Traite une requête si elle est complète dans le tampon. `true` si elle a été prise en charge.
    private func tryHandleRequest() -> Bool {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerEnd = buffer.range(of: separator) else {
            if buffer.count > maxHeaderSize { respondAndClose(.text(431, "headers too large")) ; return true }
            return false
        }
        guard let head = String(data: buffer[buffer.startIndex..<headerEnd.lowerBound], encoding: .utf8),
              let (method, target, version, headers) = Self.parseHead(head)
        else { respondAndClose(.text(400, "bad request")); return true }

        if headers["transfer-encoding"] != nil {
            respondAndClose(.text(411, "length required")); return true
        }
        let length = Int(headers["content-length"] ?? "0") ?? 0
        guard length <= maxBodySize else { respondAndClose(.text(413, "too large")); return true }

        let bodyStart = headerEnd.upperBound
        guard buffer.count - (bodyStart - buffer.startIndex) >= length else { return false }
        let body = buffer.subdata(in: bodyStart..<(bodyStart + length))
        buffer = Data(buffer[(bodyStart + length)...])

        let request = HTTPRequest(method: method, target: target, version: version, headers: headers, body: body)
        Task { await self.process(request) }
        return true
    }

    private static func parseHead(_ head: String) -> (String, String, String, [String: String])? {
        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ").map(String.init)
        guard requestLine.count == 3 else { return nil }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[name] = headers[name].map { "\($0), \(value)" } ?? value
        }
        return (requestLine[0].uppercased(), requestLine[1], requestLine[2], headers)
    }

    // MARK: - Réponse

    private func process(_ request: HTTPRequest) async {
        let response = await handler(request)
        #if DEBUG
        Log.localServer.debug("\(request.method, privacy: .public) \(request.path, privacy: .public) → \(response.status)")
        #endif
        do {
            try await send(response, for: request)
            if request.keepAlive {
                queue.async { if !self.tryHandleRequest() { self.receive() } }
            } else {
                connection.cancel()
            }
        } catch {
            connection.cancel()
        }
    }

    private func send(_ response: HTTPResponse, for request: HTTPRequest) async throws {
        var headers = response.headers
        let isHead = request.method == "HEAD"
        switch response.body {
        case .empty:
            headers.append(("Content-Length", "0"))
        case .data(let data):
            headers.append(("Content-Length", String(data.count)))
        case .stream(let length, _):
            if let length { headers.append(("Content-Length", String(length))) }
            else if !isHead { headers.append(("Transfer-Encoding", "chunked")) }
        }
        headers.append(("Connection", request.keepAlive ? "keep-alive" : "close"))

        var head = "HTTP/1.1 \(response.status) \(HTTPResponse.reason(response.status))\r\n"
        for (name, value) in headers { head += "\(name): \(value)\r\n" }
        head += "\r\n"
        do {
            try await rawSend(Data(head.utf8))
        } catch {
            // Client parti : on laisse le producteur échouer pour qu'il libère sa source (tâche amont).
            if case .stream(_, let producer) = response.body { try? await producer(ClosedWriter()) }
            throw error
        }

        guard !isHead else {
            if case .stream(_, let producer) = response.body { try? await producer(ClosedWriter()) }
            return
        }
        switch response.body {
        case .empty:
            break
        case .data(let data):
            if !data.isEmpty { try await rawSend(data) }
        case .stream(let length, let producer):
            chunked = length == nil
            try await producer(self)
            if chunked { try await rawSend(Data("0\r\n\r\n".utf8)) }
        }
    }

    /// `HTTPBodyWriter` : un morceau de corps (encodé en chunk si la longueur est inconnue).
    func write(_ data: Data) async throws {
        guard !data.isEmpty else { return }
        if chunked {
            var chunk = Data(String(data.count, radix: 16).utf8)
            chunk.append(Data("\r\n".utf8))
            chunk.append(data)
            chunk.append(Data("\r\n".utf8))
            try await rawSend(chunk)
        } else {
            try await rawSend(data)
        }
    }

    /// Envoi avec attente de l'acquittement (contre-pression naturelle).
    private func rawSend(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            })
        }
    }

    private func respondAndClose(_ response: HTTPResponse) {
        let request = HTTPRequest(method: "GET", target: "/", version: "HTTP/1.1", headers: ["connection": "close"], body: Data())
        Task {
            try? await send(response, for: request)
            connection.cancel()
        }
    }
}

/// Writer d'une connexion déjà fermée : toute écriture échoue.
private final class ClosedWriter: HTTPBodyWriter {
    func write(_ data: Data) async throws {
        throw URLError(.networkConnectionLost)
    }
}
