import XCTest
@testable import Memories

final class ProxyResponsePolicyTests: XCTestCase {
    private let server = "https://cloud.example.com"
    private let local = "http://127.0.0.1:62079"

    private func headers(_ upstream: [(String, String)]) -> [String: String] {
        let result = ProxyResponsePolicy.headers(from: upstream, serverOrigin: server, localOrigin: local)
        return Dictionary(result.map { ($0.0.lowercased(), $0.1) }, uniquingKeysWith: { _, last in last })
    }

    func testExecutableTypesBecomePlainText() {
        for type in [
            "text/javascript", "application/javascript; charset=utf-8", "APPLICATION/X-JAVASCRIPT",
            "text/html", "text/html; charset=UTF-8", "application/xhtml+xml", "application/wasm", " text/ecmascript ",
        ] {
            XCTAssertEqual(headers([("Content-Type", type)])["content-type"], "text/plain; charset=utf-8", type)
        }
    }

    func testHarmlessTypesAreKept() {
        for type in ["application/json", "image/jpeg", "video/mp4", "text/css", "application/xml; charset=utf-8", "text/plain"] {
            XCTAssertEqual(headers([("Content-Type", type)])["content-type"], type)
        }
    }

    func testNosniffAlwaysAndNeverDuplicated() {
        XCTAssertEqual(headers([("Content-Type", "image/png")])["x-content-type-options"], "nosniff")
        let result = ProxyResponsePolicy.headers(
            from: [("X-Content-Type-Options", "something"), ("Content-Type", "image/png")], serverOrigin: server, localOrigin: local
        )
        XCTAssertEqual(result.filter { $0.0.lowercased() == "x-content-type-options" }.map(\.1), ["nosniff"])
    }

    func testMarkupThatCanEmbedScriptIsSandboxed() {
        XCTAssertEqual(headers([("Content-Type", "image/svg+xml")])["content-security-policy"], "sandbox")
        XCTAssertEqual(headers([("Content-Type", "application/xml")])["content-security-policy"], "sandbox")
        XCTAssertNil(headers([("Content-Type", "image/png")])["content-security-policy"])
    }

    func testLocationOnTheServerPointsBackToTheLocalOrigin() {
        XCTAssertEqual(headers([("Location", "https://cloud.example.com/index.php/apps/files")])["location"], "http://127.0.0.1:62079/index.php/apps/files")
        XCTAssertEqual(headers([("Location", "https://other.example.org/x")])["location"], "https://other.example.org/x")
        XCTAssertEqual(headers([("Location", "/relative")])["location"], "/relative")
    }

    func testHopByHopAndRegeneratedHeadersAreDropped() {
        let result = headers([
            ("Content-Encoding", "gzip"), ("Content-Length", "10"), ("Transfer-Encoding", "chunked"),
            ("Connection", "close"), ("Set-Cookie", "a=b"), ("ETag", "\"x\""),
        ])
        for name in ["content-encoding", "content-length", "transfer-encoding", "connection", "set-cookie"] {
            XCTAssertNil(result[name], name)
        }
        XCTAssertEqual(result["etag"], "\"x\"")
    }
}
