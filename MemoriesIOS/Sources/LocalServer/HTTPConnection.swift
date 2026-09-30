import Foundation
import Network

/// A TCP connection to the local server: minimal HTTP/1.1 parsing (headers + `Content-Length`
/// body), one request at a time, keep-alive, full or streamed responses.
///
/// State is confined to `queue`; request handling runs in a `Task`.
final class HTTPConnection: HTTPBodyWriter, @unchecked Sendable {
    typealias Handler = @Sendable (HTTPRequest) async -> HTTPResponse

    private let connection: NWConnection
    private let queue = DispatchQueue(label: "memories.localserver.connection")
    private let handler: Handler
    private var buffer = Data()
    private var chunked = false

    /// Max size of a request's headers and body (web uploads go through WebDAV chunks).
    private let maxHeaderSize = 64 * 1024
    private let maxBodySize = 512 * 1024 * 1024

    init(_ connection: NWConnection, handler: @escaping Handler) {
        self.connection = connection
        self.handler = handler
    }

    /// Starts the connection. The handlers retain `self` until it closes
    /// (nothing else holds a reference to the connection).
    func start() {
        connection.stateUpdateHandler = { state in
            switch state {
            case .failed:
                self.connection.cancel()
            case .cancelled:
                self.connection.stateUpdateHandler = nil // breaks the retain cycle
            default:
                break
            }
        }
        connection.start(queue: queue)
        receive()
    }

    // MARK: - Reading

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { data, _, isComplete, error in
            if let data { self.buffer.append(data) }
            if error != nil { return self.connection.cancel() }
            if self.tryHandleRequest() { return }
            if isComplete { return self.connection.cancel() }
            self.receive()
        }
    }

    /// Handles a request if it is complete in the buffer. Returns `true` if it was handled.
    private func tryHandleRequest() -> Bool {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerEnd = buffer.range(of: separator) else {
            if buffer.count > maxHeaderSize { respondAndClose(.text(431, "headers too large")) ; return true }
            return false
        }
        guard let text = String(data: buffer[buffer.startIndex..<headerEnd.lowerBound], encoding: .utf8),
              let head = HTTPRequestHead(text)
        else { respondAndClose(.text(400, "bad request")); return true }

        if head.headers["transfer-encoding"] != nil {
            respondAndClose(.text(411, "length required")); return true
        }
        let length = Int(head.headers["content-length"] ?? "0") ?? 0
        guard length <= maxBodySize else { respondAndClose(.text(413, "too large")); return true }

        let bodyStart = headerEnd.upperBound
        guard buffer.count - (bodyStart - buffer.startIndex) >= length else { return false }
        let body = buffer.subdata(in: bodyStart..<(bodyStart + length))
        buffer = Data(buffer[(bodyStart + length)...])

        let request = HTTPRequest(
            method: head.method, target: head.target, version: head.version, headers: head.headers, body: body
        )
        Task { await self.process(request) }
        return true
    }

    // MARK: - Response

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
            // Client gone: let the producer fail so it releases its source (upstream task).
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

    /// `HTTPBodyWriter`: one piece of the body (chunk-encoded if the length is unknown).
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

    /// Sends and waits for the acknowledgement (natural backpressure).
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

/// Writer for an already closed connection: every write fails.
private final class ClosedWriter: HTTPBodyWriter {
    func write(_ data: Data) async throws {
        throw URLError(.networkConnectionLost)
    }
}
