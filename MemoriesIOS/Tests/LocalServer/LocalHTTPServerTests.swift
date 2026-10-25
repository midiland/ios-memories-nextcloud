import Network
import XCTest
@testable import Memories

/// Listener lifecycle on a real socket (free port, not the app's 62079).
///
/// iOS reclaims the listening socket of a suspended app: the server is suspended in the
/// background and must listen again, on the same port (same page origin), when the app returns.
@MainActor
final class LocalHTTPServerTests: XCTestCase {
    private var server: LocalHTTPServer!

    override func setUp() async throws {
        server = LocalHTTPServer(preferredPort: 0)
    }

    override func tearDown() async throws {
        server.suspend()
    }

    func testAnswersOnceStarted() async throws {
        let port = try await server.ensureStarted()
        XCTAssertNotEqual(port, 0)
        let status = await statusCode()
        XCTAssertEqual(status, 403) // no `local-auth` cookie
    }

    func testStopsListeningWhenSuspended() async throws {
        try await server.ensureStarted()
        server.suspend()
        let status = await statusCode()
        XCTAssertNil(status)
    }

    func testListensAgainOnTheSamePortAfterSuspension() async throws {
        let port = try await server.ensureStarted()
        for _ in 0..<2 {
            server.suspend()
            let restarted = try await server.ensureStarted()
            XCTAssertEqual(restarted, port)
            let status = await statusCode()
            XCTAssertEqual(status, 403)
        }
    }

    func testEnsureStartedKeepsARunningListener() async throws {
        let port = try await server.ensureStarted()
        let again = try await server.ensureStarted()
        XCTAssertEqual(again, port)
    }

    func testNegativeContentLengthDoesNotCrashTheServer() async throws {
        let port = try await server.ensureStarted()
        let reply = await rawExchange(port: port, request: "POST / HTTP/1.1\r\nHost: 127.0.0.1:\(port)\r\nContent-Length: -5\r\n\r\n")
        XCTAssertTrue(reply?.hasPrefix("HTTP/1.1 400") == true, reply ?? "no reply")
        let status = await statusCode()
        XCTAssertEqual(status, 403) // still alive
    }

    func testUnauthenticatedHugeBodyIsRefusedFromTheHeaders() async throws {
        let port = try await server.ensureStarted()
        // The body never arrives: the 403 must come from the headers alone.
        let reply = await rawExchange(port: port, request: "POST / HTTP/1.1\r\nHost: 127.0.0.1:\(port)\r\nContent-Length: 50000000\r\n\r\n")
        XCTAssertTrue(reply?.hasPrefix("HTTP/1.1 403") == true, reply ?? "no reply")
    }

    func testConnectionLimiter() {
        let limiter = ConnectionLimiter(maxConnections: 2)
        XCTAssertTrue(limiter.acquire())
        XCTAssertTrue(limiter.acquire())
        XCTAssertFalse(limiter.acquire())
        limiter.release()
        XCTAssertTrue(limiter.acquire())
        limiter.release(); limiter.release(); limiter.release() // never below zero
        XCTAssertTrue(limiter.acquire())
    }

    // MARK: - Helpers

    /// Sends raw bytes and returns the beginning of the reply (`nil` if none within 3 s).
    private func rawExchange(port: UInt16, request: String) async -> String? {
        let connection = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
        defer { connection.cancel() }
        connection.start(queue: .global())
        return await withCheckedContinuation { continuation in
            let once = Once()
            DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
                if once.claim() { continuation.resume(returning: nil) }
            }
            connection.send(content: Data(request.utf8), completion: .contentProcessed { _ in
                connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, _, _ in
                    if once.claim() { continuation.resume(returning: data.flatMap { String(data: $0, encoding: .utf8) }) }
                }
            })
        }
    }

    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false
        func claim() -> Bool { lock.withLock { defer { done = true }; return !done } }
    }

    /// Status of a request on a new connection (no keep-alive reuse), `nil` if refused.
    private func statusCode() async -> Int? {
        var request = URLRequest(url: server.origin.appendingPathComponent("favicon.ico"))
        request.timeoutInterval = 2
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        guard let (_, response) = try? await session.data(for: request) else { return nil }
        return (response as? HTTPURLResponse)?.statusCode
    }
}
