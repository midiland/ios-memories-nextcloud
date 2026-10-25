import XCTest
@testable import Memories

/// Tests for `NextcloudClient`'s remote-wipe methods (issue #15).
///
/// Uses `MockURLProtocol` to exercise the real request building and response
/// parsing: method, URL, headers, form body, and status-code interpretation.
final class RemoteWipeClientTests: XCTestCase {
    private var client: NextcloudClient!

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
        client = NextcloudClient(session: mockSession())
    }

    override func tearDown() {
        client = nil
        MockURLProtocol.reset()
        super.tearDown()
    }

    // MARK: - checkWipe: response interpretation

    func testCheckWipeReturnsTrueOn200WipeTrue() async throws {
        MockURLProtocol.response = (Data(#"{"wipe": true}"#.utf8), 200, ["Content-Type": "application/json"])
        let result = try await client.checkWipe(Fixtures.credentials)
        XCTAssertTrue(result)
    }

    func testCheckWipeReturnsFalseOn404() async throws {
        MockURLProtocol.response = (Data(), 404, [:])
        let result = try await client.checkWipe(Fixtures.credentials)
        XCTAssertFalse(result)
    }

    func testCheckWipeThrowsOn500() async {
        MockURLProtocol.response = (Data(), 500, [:])
        do {
            _ = try await client.checkWipe(Fixtures.credentials)
            XCTFail("500 must throw")
        } catch AppError.unexpectedStatus(500) {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCheckWipeThrowsOnInvalidJSON() async {
        MockURLProtocol.response = (Data("not json".utf8), 200, [:])
        do {
            _ = try await client.checkWipe(Fixtures.credentials)
            XCTFail("Invalid JSON must throw")
        } catch AppError.invalidResponse {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCheckWipeThrowsOnMissingWipeKey() async {
        MockURLProtocol.response = (Data(#"{"other": true}"#.utf8), 200, [:])
        do {
            _ = try await client.checkWipe(Fixtures.credentials)
            XCTFail("Missing wipe key must throw")
        } catch AppError.invalidResponse {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCheckWipeThrowsOnNetworkError() async {
        MockURLProtocol.error = URLError(.notConnectedToInternet)
        do {
            _ = try await client.checkWipe(Fixtures.credentials)
            XCTFail("Network error must throw")
        } catch AppError.serverUnreachable {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - checkWipe: request shape

    func testCheckWipeRequestShape() async throws {
        MockURLProtocol.response = (Data(), 404, [:])
        _ = try await client.checkWipe(Fixtures.credentials)

        let request = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://cloud.example.com/nextcloud/index.php/core/wipe/check"
        )
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Content-Type"),
            "application/x-www-form-urlencoded"
        )
        // The endpoint is #[PublicPage]: no Basic auth, the token is the credential.
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(
            String(data: try XCTUnwrap(MockURLProtocol.lastBody), encoding: .utf8),
            "token=secret"
        )
    }

    func testCheckWipeUsesNextcloudRootNotMemoriesApp() async throws {
        MockURLProtocol.response = (Data(), 404, [:])
        _ = try await client.checkWipe(Fixtures.credentials)
        let url = try XCTUnwrap(MockURLProtocol.lastRequest?.url?.absoluteString)
        XCTAssertTrue(url.hasPrefix("https://cloud.example.com/nextcloud/index.php/core/wipe/"))
        XCTAssertFalse(url.contains("/apps/memories/"))
    }

    func testCheckWipePercentEncodesToken() async throws {
        // A token with +, & or = must be percent-encoded in the form body.
        let special = Credentials(server: Fixtures.server, loginName: "alice", appPassword: "abc+def&ghi=jkl")
        MockURLProtocol.response = (Data(), 404, [:])
        _ = try await client.checkWipe(special)

        let body = String(data: try XCTUnwrap(MockURLProtocol.lastBody), encoding: .utf8)
        XCTAssertTrue(body?.hasPrefix("token=") == true)
        let value = String(body?.dropFirst("token=".count) ?? "")
        XCTAssertFalse(value.contains("+"), "raw + must be encoded")
        XCTAssertFalse(value.contains("&"), "raw & must be encoded")
        XCTAssertFalse(value.contains("="), "raw = in the value must be encoded")
        // Round-trip: decoding must give the original token.
        XCTAssertEqual(value.removingPercentEncoding, "abc+def&ghi=jkl")
    }

    // MARK: - confirmWipe: response interpretation

    func testConfirmWipeReturnsTrueOn200() async {
        MockURLProtocol.response = (Data(), 200, [:])
        let result = await client.confirmWipe(Fixtures.credentials)
        XCTAssertTrue(result)
    }

    func testConfirmWipeReturnsTrueOn404() async {
        // After a wipe is confirmed, the token no longer exists: 404 means
        // "already confirmed" — nothing left to do, so it is a success.
        MockURLProtocol.response = (Data(), 404, [:])
        let result = await client.confirmWipe(Fixtures.credentials)
        XCTAssertTrue(result)
    }

    func testConfirmWipeReturnsFalseOn500() async {
        MockURLProtocol.response = (Data(), 500, [:])
        let result = await client.confirmWipe(Fixtures.credentials)
        XCTAssertFalse(result)
    }

    func testConfirmWipeReturnsFalseOn429() async {
        // Rate limited: retry later.
        MockURLProtocol.response = (Data(), 429, [:])
        let result = await client.confirmWipe(Fixtures.credentials)
        XCTAssertFalse(result)
    }

    func testConfirmWipeReturnsFalseOnNetworkError() async {
        MockURLProtocol.error = URLError(.notConnectedToInternet)
        let result = await client.confirmWipe(Fixtures.credentials)
        XCTAssertFalse(result)
    }

    // MARK: - confirmWipe: request shape

    func testConfirmWipeRequestShape() async throws {
        MockURLProtocol.response = (Data(), 200, [:])
        _ = await client.confirmWipe(Fixtures.credentials)

        let request = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://cloud.example.com/nextcloud/index.php/core/wipe/success"
        )
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Content-Type"),
            "application/x-www-form-urlencoded"
        )
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(
            String(data: try XCTUnwrap(MockURLProtocol.lastBody), encoding: .utf8),
            "token=secret"
        )
    }

    func testConfirmWipeSendsTokenForDifferentAccount() async throws {
        let other = Credentials(server: Fixtures.server, loginName: "bob", appPassword: "hunter2")
        MockURLProtocol.response = (Data(), 200, [:])
        _ = await client.confirmWipe(other)
        let body = String(data: try XCTUnwrap(MockURLProtocol.lastBody), encoding: .utf8)
        XCTAssertEqual(body, "token=hunter2")
    }
}
