import Foundation

/// Relais des requêtes non locales vers Nextcloud (port de `ProxyController.kt`).
///
/// - ajoute `Authorization: Basic` et `OCS-APIREQUEST: true` (exempte de la vérification CSRF,
///   donc pas besoin de jeton de requête dans la page locale) ;
/// - garde les cookies de session Nextcloud dans `HTTPCookieStorage.shared` : les requêtes
///   suivantes évitent un login complet côté serveur (~17× plus rapide d'après Android) ;
/// - diffuse la réponse en continu (vidéos, gros fichiers) avec contre-pression ;
/// - réseau indisponible → 504, que le frontend interprète comme « hors ligne ».
final class UpstreamProxy: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    /// En-têtes du client à ne pas transmettre (connexion, cookies locaux, compression).
    private static let skippedRequestHeaders: Set<String> = [
        "host", "content-length", "transfer-encoding", "connection", "cookie",
        "accept-encoding", "expect", "authorization", "origin", "referer",
    ]
    /// En-têtes amont régénérés localement (URLSession décompresse déjà le corps).
    private static let skippedResponseHeaders: Set<String> = [
        "content-encoding", "transfer-encoding", "content-length", "connection", "keep-alive", "set-cookie",
    ]

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = .shared
        config.httpShouldSetCookies = true
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 7 * 24 * 3600
        config.requestCachePolicy = .reloadIgnoringLocalCacheData // WebKit gère son propre cache
        config.urlCache = nil
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        return URLSession(configuration: config, delegate: self, delegateQueue: queue)
    }()

    private let lock = NSLock()
    private var streams: [Int: ResponseStream] = [:]

    // MARK: - Relais

    func forward(_ request: HTTPRequest, config: LocalAppConfig, localOrigin: String) async -> HTTPResponse {
        guard let url = URL(string: config.server.origin.absoluteString + request.target) else {
            return .text(400, "bad target")
        }
        var upstream = URLRequest(url: url)
        upstream.httpMethod = request.method
        for (name, value) in request.headers where !Self.skippedRequestHeaders.contains(name) {
            upstream.setValue(value, forHTTPHeaderField: name)
        }
        upstream.setValue(config.credentials.basicAuthHeader, forHTTPHeaderField: "Authorization")
        upstream.setValue("true", forHTTPHeaderField: "OCS-APIREQUEST")
        if !request.body.isEmpty || ["POST", "PUT", "PATCH", "PROPPATCH", "REPORT"].contains(request.method) {
            upstream.httpBody = request.body
        }

        let stream = ResponseStream()
        let task = session.dataTask(with: upstream)
        stream.task = task
        lock.withLock { streams[task.taskIdentifier] = stream }
        task.resume()

        let head: HTTPURLResponse
        do {
            head = try await stream.response()
        } catch {
            return .text(504, "upstream unreachable")
        }
        return response(for: head, stream: stream, config: config, localOrigin: localOrigin)
    }

    /// Construit la réponse locale : en-têtes filtrés, `Location` réécrite, corps en flux.
    private func response(
        for head: HTTPURLResponse, stream: ResponseStream, config: LocalAppConfig, localOrigin: String
    ) -> HTTPResponse {
        var headers: [(String, String)] = []
        let serverOrigin = config.server.origin.absoluteString
        for case let (name as String, value as String) in head.allHeaderFields {
            let lower = name.lowercased()
            if Self.skippedResponseHeaders.contains(lower) { continue }
            if lower == "location", value.hasPrefix(serverOrigin) {
                headers.append((name, localOrigin + value.dropFirst(serverOrigin.count)))
            } else {
                headers.append((name, value))
            }
        }

        // Longueur connue seulement si le corps n'a pas été décompressé en route.
        let compressed = head.value(forHTTPHeaderField: "Content-Encoding").map { !$0.isEmpty && $0 != "identity" } ?? false
        let length = !compressed && head.expectedContentLength >= 0 ? Int(head.expectedContentLength) : nil

        return HTTPResponse(status: head.statusCode, headers: headers, body: .stream(length: length) { writer in
            do {
                for try await chunk in stream.chunks {
                    try await writer.write(chunk)
                    stream.consumed(chunk.count)
                }
            } catch {
                stream.task?.cancel()
                throw error
            }
        })
    }

    // MARK: - URLSessionDataDelegate (file série)

    func urlSession(
        _ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        stream(for: dataTask)?.receive(response)
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        stream(for: dataTask)?.receive(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let stream = lock.withLock { streams.removeValue(forKey: task.taskIdentifier) }
        stream?.complete(error)
    }

    private func stream(for task: URLSessionTask) -> ResponseStream? {
        lock.withLock { streams[task.taskIdentifier] }
    }
}

/// Pont entre les callbacks URLSession et le flux asynchrone consommé par la connexion locale.
/// Suspend la tâche amont quand trop de données attendent (le client lit moins vite).
private final class ResponseStream: @unchecked Sendable {
    private static let highWater = 8 * 1024 * 1024
    private static let lowWater = 2 * 1024 * 1024

    weak var task: URLSessionDataTask?
    let chunks: AsyncThrowingStream<Data, Error>
    private let continuation: AsyncThrowingStream<Data, Error>.Continuation
    private let lock = NSLock()
    private var headContinuation: CheckedContinuation<HTTPURLResponse, Error>?
    private var head: Result<HTTPURLResponse, Error>?
    private var pending = 0
    private var suspended = false

    init() {
        var continuation: AsyncThrowingStream<Data, Error>.Continuation!
        chunks = AsyncThrowingStream { continuation = $0 }
        self.continuation = continuation
    }

    /// Attend les en-têtes de la réponse amont.
    func response() async throws -> HTTPURLResponse {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if let head {
                lock.unlock()
                continuation.resume(with: head)
            } else {
                headContinuation = continuation
                lock.unlock()
            }
        }
    }

    func receive(_ response: URLResponse) {
        guard let http = response as? HTTPURLResponse else { return resolveHead(.failure(URLError(.badServerResponse))) }
        resolveHead(.success(http))
    }

    func receive(_ data: Data) {
        continuation.yield(data)
        lock.lock()
        pending += data.count
        let shouldSuspend = !suspended && pending > Self.highWater
        if shouldSuspend { suspended = true }
        lock.unlock()
        if shouldSuspend { task?.suspend() }
    }

    func consumed(_ count: Int) {
        lock.lock()
        pending -= count
        let shouldResume = suspended && pending < Self.lowWater
        if shouldResume { suspended = false }
        lock.unlock()
        if shouldResume { task?.resume() }
    }

    func complete(_ error: Error?) {
        resolveHead(.failure(error ?? URLError(.badServerResponse)))
        if let error { continuation.finish(throwing: error) } else { continuation.finish() }
    }

    /// Délivre les en-têtes (ou l'erreur) une seule fois.
    private func resolveHead(_ result: Result<HTTPURLResponse, Error>) {
        lock.lock()
        guard head == nil else { return lock.unlock() }
        head = result
        let waiting = headContinuation
        headContinuation = nil
        lock.unlock()
        waiting?.resume(with: result)
    }
}
