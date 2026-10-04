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

    // MARK: - Helpers

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
