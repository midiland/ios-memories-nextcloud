import Foundation
import Network

/// A TCP connection to the local server: minimal HTTP/1.1 parsing (headers + `Content-Length`
/// body), one request at a time, keep-alive, full or streamed responses.
///
/// Reading (`buffer`) happens on `queue`. A request is then handled and its response written
/// in a `Task` (`chunked`, `send`, `write`); this is safe because a connection handles one request
/// at a time: reading only resumes once the response has been sent.
final class HTTPConnection: HTTPBodyWriter, @unchecked Sendable {
    typealias Handler = @Sendable (HTTPRequest) async -> HTTPResponse
    /// Called as soon as the headers are complete, before the body is read: a non-nil response
    /// is sent as-is and the connection is closed (access control without buffering the body).
    typealias Preflight = @Sendable (HTTPRequestHead) -> HTTPResponse?

    private let connection: NWConnection
    private let queue = DispatchQueue(label: "memories.localserver.connection")
    private let handler: Handler
    private let preflight: Preflight
    private let onClose: @Sendable () -> Void
    private var buffer = Data()
    private var chunked = false
    private var preflightPassed = false
    private var timeout: DispatchWorkItem?

    /// Max time without bytes: in the middle of a request (slowloris), and between two requests.
    static let requestTimeout: TimeInterval = 30
    static let idleTimeout: TimeInterval = 120

    init(
        _ connection: NWConnection,
        preflight: @escaping Preflight = { _ in nil },
        onClose: @escaping @Sendable () -> Void = {},
        handler: @escaping Handler
    ) {
        self.connection = connection
        self.preflight = preflight
        self.onClose = onClose
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
                self.timeout?.cancel()
                self.onClose()
            default:
                break
            }
        }
        connection.start(queue: queue)
        receive()
    }

    // MARK: - Reading

    private func receive() {
        armTimeout(buffer.isEmpty ? Self.idleTimeout : Self.requestTimeout)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { data, _, isComplete, error in
            if let data { self.buffer.append(data) }
            if error != nil { return self.connection.cancel() }
            if self.tryHandleRequest() { return }
            if isComplete { return self.connection.cancel() }
            self.receive()
        }
    }

    /// Closes the connection if no byte arrives in time (cancelled once a request is being handled).
    private func armTimeout(_ interval: TimeInterval) {
        timeout?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.connection.cancel() }
        timeout = item
        queue.asyncAfter(deadline: .now() + interval, execute: item)
    }

    /// Handles a request if it is complete in the buffer. Returns `true` if it was handled.
    private func tryHandleRequest() -> Bool {
        switch HTTPRequestParser.parse(buffer) {
        case .incomplete:
            return false
        case .rejected(let status, let message):
            respondAndClose(.text(status, message)); return true
        case .head(let head, let bodyOffset, let length):
            return handle(head, bodyOffset: bodyOffset, length: length)
        }
    }

    private func handle(_ head: HTTPRequestHead, bodyOffset: Int, length: Int) -> Bool {
        if !preflightPassed {
            if let response = preflight(head) { respondAndClose(response); return true }
            preflightPassed = true
        }
        guard buffer.count - bodyOffset >= length else { return false }
        let bodyStart = buffer.startIndex + bodyOffset
        let body = buffer.subdata(in: bodyStart..<(bodyStart + length))
        buffer = Data(buffer[(bodyStart + length)...])
        preflightPassed = false
        timeout?.cancel()

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
