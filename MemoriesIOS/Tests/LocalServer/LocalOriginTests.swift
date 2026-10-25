import XCTest
@testable import Memories

final class LocalOriginTests: XCTestCase {
    private func url(_ text: String) -> URL { URL(string: text)! }

    func testMatchesOnlyTheLocalServerPort() {
        XCTAssertTrue(LocalOrigin.matches(url("http://127.0.0.1:62079/nextcloud/"), localPort: 62079))
        XCTAssertTrue(LocalOrigin.matches(url("http://localhost:62079/"), localPort: 62079))
        XCTAssertFalse(LocalOrigin.matches(url("http://127.0.0.1:9999/"), localPort: 62079))
        XCTAssertFalse(LocalOrigin.matches(url("http://127.0.0.1/"), localPort: 62079)) // default port 80
        XCTAssertFalse(LocalOrigin.matches(url("https://127.0.0.1:62079/"), localPort: 62079))
        XCTAssertFalse(LocalOrigin.matches(url("http://evil.example.org:62079/"), localPort: 62079))
        XCTAssertFalse(LocalOrigin.matches(url("http://127.0.0.1.evil.example.org:62079/"), localPort: 62079))
        XCTAssertFalse(LocalOrigin.matches(url("http://127.0.0.1:62079@evil.example.org/"), localPort: 62079))
    }

    func testNothingMatchesBeforeTheServerListens() {
        XCTAssertFalse(LocalOrigin.matches(url("http://127.0.0.1:0/"), localPort: 0))
        XCTAssertFalse(LocalOrigin.matches(url("http://127.0.0.1/"), localPort: 0))
    }

    func testOnlyTheLocalMainFrameIsTrusted() {
        func trusted(main: Bool, host: String = "127.0.0.1", port: Int = 62079, scheme: String = "http") -> Bool {
            LocalOrigin.isTrustedFrame(isMainFrame: main, scheme: scheme, host: host, port: port, localPort: 62079)
        }
        XCTAssertTrue(trusted(main: true))
        XCTAssertFalse(trusted(main: false)) // sub-frame, even on the local origin
        XCTAssertFalse(trusted(main: true, host: "www.openstreetmap.org", port: 443, scheme: "https"))
        XCTAssertFalse(trusted(main: true, port: 9999))
    }

    func testCrossSiteMutations() {
        func cross(_ method: String, _ headers: [String: String] = [:]) -> Bool {
            LocalOrigin.isCrossSiteMutation(method: method, headers: headers, localPort: 62079)
        }
        // Safe methods are never blocked.
        XCTAssertFalse(cross("GET", ["sec-fetch-site": "cross-site"]))
        XCTAssertFalse(cross("OPTIONS", ["origin": "https://evil.example.org"]))
        // Sec-Fetch-Site wins when present.
        XCTAssertTrue(cross("POST", ["sec-fetch-site": "cross-site"]))
        XCTAssertTrue(cross("DELETE", ["sec-fetch-site": "same-site"]))
        XCTAssertFalse(cross("POST", ["sec-fetch-site": "same-origin"]))
        XCTAssertFalse(cross("PUT", ["sec-fetch-site": "none"]))
        // Otherwise Origin.
        XCTAssertFalse(cross("POST", ["origin": "http://127.0.0.1:62079"]))
        XCTAssertTrue(cross("POST", ["origin": "http://127.0.0.1:9999"]))
        XCTAssertTrue(cross("POST", ["origin": "https://evil.example.org"]))
        XCTAssertTrue(cross("POST", ["origin": "null"]))
        // No browser header: not a page request.
        XCTAssertFalse(cross("PROPFIND"))
    }
}
