import Foundation
import Network

/// Serveur HTTP sur `127.0.0.1` (équivalent de `LocalHttpServer.kt`) : sert la page locale et
/// le snapshot, et relaie le reste vers Nextcloud. Toute l'app web est ainsi *same-origin*.
///
/// - Port fixe (62079, comme Android) pour que l'origine — donc le localStorage et le
///   cache du frontend — reste identique d'un lancement à l'autre ; port libre en secours.
/// - Le port n'est pas un secret (toute app de l'appareil peut s'y connecter) : chaque
///   requête doit porter le cookie HttpOnly `local-auth` (secret par processus).
/// - iOS peut invalider le socket en arrière-plan : `ensureStarted()` le relance au retour.
@MainActor
final class LocalHTTPServer {
    static let shared = LocalHTTPServer()
    nonisolated static let host = "127.0.0.1"
    nonisolated static let preferredPort: UInt16 = 62079

    /// Secret du cookie `local-auth`, régénéré à chaque lancement de l'app.
    nonisolated let secret = UUID().uuidString
    let router: LocalRouter

    private(set) var port: UInt16 = 0
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "memories.localserver.listener")

    private init() {
        router = LocalRouter(secret: secret)
    }

    var origin: URL { URL(string: "http://\(Self.host):\(port)")! }

    /// Démarre l'écoute si besoin et renvoie le port.
    @discardableResult
    func ensureStarted() async throws -> UInt16 {
        if listener != nil { return port }
        do {
            port = try await listen(on: Self.preferredPort)
        } catch {
            // Port occupé : port libre, l'origine change pour cette session seulement.
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

    /// Socket perdu (arrière-plan, erreur) : le prochain `ensureStarted()` relancera l'écoute.
    private func listenerDidStop(_ stopped: NWListener) {
        if listener === stopped { listener = nil }
    }
}

/// Garantit qu'une continuation n'est reprise qu'une fois (callbacks d'état multiples).
private final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    /// `true` au premier appel seulement.
    func claim() -> Bool {
        lock.withLock {
            defer { claimed = true }
            return !claimed
        }
    }
}
