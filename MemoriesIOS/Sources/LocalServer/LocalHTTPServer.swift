import Foundation
import Network

/// HTTP server on `127.0.0.1` (counterpart of `LocalHttpServer.kt`): serves the local page and
/// the snapshot, and proxies everything else to Nextcloud. The whole web app is thus *same-origin*.
///
/// - Fixed port (62079, same as Android) so the origin — and therefore the frontend's
///   localStorage and cache — stays the same across launches; falls back to a free port.
/// - The port is not a secret (any app on the device can connect to it): every
///   request must carry the HttpOnly `local-auth` cookie (a per-process secret).
/// - iOS reclaims listening sockets of suspended apps: the app calls `suspend()` when it goes to
///   the background and `ensureStarted()` on return, which binds the same port again (same origin).
///   A listener that fails anyway is restarted right away.
@MainActor
final class LocalHTTPServer {
    static let shared = LocalHTTPServer()
    nonisolated static let host = "127.0.0.1"

    /// Secret for the `local-auth` cookie, regenerated on every app launch.
    nonisolated let secret = UUID().uuidString
    let router: LocalRouter
    /// Port tried first; 62079 for the app, 0 (any free port) in tests.
    private let preferredPort: UInt16

    private(set) var port: UInt16 = 0
    private var listener: NWListener?
    /// Stopped on purpose (background): a failure must not restart it.
    private var isSuspended = false
    /// Start in progress, awaited by concurrent `ensureStarted()` calls.
    private var starting: Task<UInt16, Error>?
    private let queue = DispatchQueue(label: "memories.localserver.listener")

    init(preferredPort: UInt16 = 62079) {
        self.preferredPort = preferredPort
        router = LocalRouter(secret: secret)
    }

    var origin: URL { URL(string: "http://\(Self.host):\(port)")! }

    /// Starts listening if needed and returns the port. Concurrent callers share the same
    /// start, so the server never binds twice (the second bind would fall back to a random port).
    @discardableResult
    func ensureStarted() async throws -> UInt16 {
        isSuspended = false
        if listener != nil { return port }
        if let starting { return try await starting.value }
        let task = Task { try await bind() }
        starting = task
        defer { starting = nil }
        return try await task.value
    }

    /// Stops listening while the app is in the background (open connections are left alone).
    func suspend() {
        isSuspended = true
        guard let listener else { return }
        self.listener = nil
        listener.cancel()
        Log.localServer.notice("Listener suspended")
    }

    private func bind() async throws -> UInt16 {
        // Same port as before when restarting, so the page origin does not change.
        let isRestart = port != 0
        do {
            port = try await listen(on: isRestart ? port : preferredPort, attempts: isRestart ? 10 : 1)
        } catch {
            // Port in use: take a free port; the origin changes for this session only.
            port = try await listen(on: 0)
        }
        router.port = port
        Log.localServer.notice("Listening on port \(self.port)")
        return port
    }

    /// The suspended listener releases its port asynchronously: a restart retries for up to ~0.5 s.
    private func listen(on port: UInt16, attempts: Int) async throws -> UInt16 {
        for _ in 1..<attempts {
            if let bound = try? await listen(on: port) { return bound }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return try await listen(on: port)
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
            // Runs on `queue`, not on the main actor.
            listener.stateUpdateHandler = { @Sendable [weak self] state in
                switch state {
                case .ready:
                    if once.claim() { continuation.resume(returning: listener.port?.rawValue ?? port) }
                case .failed(let error):
                    listener.cancel()
                    if once.claim() { continuation.resume(throwing: error) }
                    Log.localServer.error("Listener failed: \(String(describing: error), privacy: .public)")
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

    /// Socket lost while in use: listen again at once (the page keeps loading from this origin).
    private func listenerDidStop(_ stopped: NWListener) {
        guard listener === stopped else { return }
        listener = nil
        guard !isSuspended else { return }
        Task { try? await ensureStarted() }
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
