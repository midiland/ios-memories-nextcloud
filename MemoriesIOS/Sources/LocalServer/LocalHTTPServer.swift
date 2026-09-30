import Foundation
import Network

/// HTTP server on `127.0.0.1` (counterpart of `LocalHttpServer.kt`): serves the local page and
/// the snapshot, and proxies everything else to Nextcloud. The whole web app is thus *same-origin*.
///
/// - Fixed port (62079, same as Android) so the origin — and therefore the frontend's
///   localStorage and cache — stays the same across launches; falls back to a free port.
/// - The port is not a secret (any app on the device can connect to it): every
///   request must carry the HttpOnly `local-auth` cookie (a per-process secret).
/// - iOS may invalidate the socket in the background: `ensureStarted()` restarts it on return.
@MainActor
final class LocalHTTPServer {
    static let shared = LocalHTTPServer()
    nonisolated static let host = "127.0.0.1"
    nonisolated static let preferredPort: UInt16 = 62079

    /// Secret for the `local-auth` cookie, regenerated on every app launch.
    nonisolated let secret = UUID().uuidString
    let router: LocalRouter

    private(set) var port: UInt16 = 0
    private var listener: NWListener?
    /// Start in progress, awaited by concurrent `ensureStarted()` calls.
    private var starting: Task<UInt16, Error>?
    private let queue = DispatchQueue(label: "memories.localserver.listener")

    private init() {
        router = LocalRouter(secret: secret)
    }

    var origin: URL { URL(string: "http://\(Self.host):\(port)")! }

    /// Starts listening if needed and returns the port. Concurrent callers share the same
    /// start, so the server never binds twice (the second bind would fall back to a random port).
    @discardableResult
    func ensureStarted() async throws -> UInt16 {
        if listener != nil { return port }
        if let starting { return try await starting.value }
        let task = Task { try await bind() }
        starting = task
        defer { starting = nil }
        return try await task.value
    }

    private func bind() async throws -> UInt16 {
        do {
            port = try await listen(on: Self.preferredPort)
        } catch {
            // Port in use: take a free port; the origin changes for this session only.
            port = try await listen(on: 0)
        }
        router.port = port
        return port
    }

    private func listen(on port: UInt16) async throws -> UInt16 {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = .hostPort(
            host: NWEndpoint.Host(Self.host), port: NWEndpoint.Port(rawValue: port) ?? .any
        )
        let listener = try NWListener(using: parameters)
        let router = self.router
        listener.newConnectionHandler = { connection in
            HTTPConnection(connection) { request in await router.handle(request) }.start()
        }

        let bound: UInt16 = try await withCheckedThrowingContinuation { continuation in
            let once = OnceFlag()
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    if once.claim() { continuation.resume(returning: listener.port?.rawValue ?? port) }
                case .failed(let error):
                    listener.cancel()
                    if once.claim() { continuation.resume(throwing: error) }
                    Task { @MainActor in self?.listenerDidStop(listener) }
                case .cancelled:
                    Task { @MainActor in self?.listenerDidStop(listener) }
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
        self.listener = listener
        return bound
    }

    /// Socket lost (background, error): the next `ensureStarted()` will restart listening.
    private func listenerDidStop(_ stopped: NWListener) {
        if listener === stopped { listener = nil }
    }
}

/// Ensures a continuation is resumed only once (multiple state callbacks).
private final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    /// `true` on the first call only.
    func claim() -> Bool {
        lock.withLock {
            defer { claimed = true }
            return !claimed
        }
    }
}
