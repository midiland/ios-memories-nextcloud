import XCTest
@testable import Memories

final class HTTPTypesTests: XCTestCase {
    func testParsesRequestHead() throws {
        let head = try XCTUnwrap(HTTPRequestHead("get /apps/x?a=1 HTTP/1.1\r\nHost: 127.0.0.1\r\nX-Multi: a\r\nx-multi: b\r\nbroken line"))
        XCTAssertEqual(head.method, "GET")
        XCTAssertEqual(head.target, "/apps/x?a=1")
        XCTAssertEqual(head.version, "HTTP/1.1")
        XCTAssertEqual(head.headers["host"], "127.0.0.1")
        XCTAssertEqual(head.headers["x-multi"], "a, b")
        XCTAssertEqual(head.headers.count, 2)
    }

    func testHeaderValueMayContainColons() throws {
        let head = try XCTUnwrap(HTTPRequestHead("GET / HTTP/1.1\r\nHost: 127.0.0.1:62079"))
        XCTAssertEqual(head.headers["host"], "127.0.0.1:62079")
    }

    func testRejectsMalformedRequestLine() {
        XCTAssertNil(HTTPRequestHead("GET /\r\nHost: x"))
        XCTAssertNil(HTTPRequestHead(""))
    }

    func testPathDropsQuery() {
        XCTAssertEqual(Fixtures.request("/a/b?c=d").path, "/a/b")
        XCTAssertEqual(Fixtures.request("?x").path, "")
    }

    func testParsesCookies() {
        let request = Fixtures.request("/", headers: ["Cookie": "local-auth=abc; theme = dark; flag; b64=a=b"])
        XCTAssertEqual(request.cookies, ["local-auth": "abc", "theme": "dark", "b64": "a=b"])
        XCTAssertEqual(Fixtures.request("/").cookies, [:])
    }

    func testKeepAliveDefaults() {
        XCTAssertTrue(Fixtures.request("/").keepAlive)
        XCTAssertFalse(Fixtures.request("/", headers: ["Connection": "Close"]).keepAlive)
        XCTAssertFalse(Fixtures.request("/", version: "HTTP/1.0").keepAlive)
        XCTAssertTrue(Fixtures.request("/", headers: ["Connection": "keep-alive"], version: "HTTP/1.0").keepAlive)
    }

    func testWantsDocument() {
        XCTAssertTrue(Fixtures.request("/", headers: ["Accept": "text/html,application/xhtml+xml"]).wantsDocument)
        XCTAssertTrue(Fixtures.request("/", headers: ["Sec-Fetch-Dest": "document"]).wantsDocument)
        XCTAssertFalse(Fixtures.request("/", headers: ["Accept": "application/json"]).wantsDocument)
    }

    func testReasonPhrases() {
        XCTAssertEqual(HTTPResponse.reason(404), "Not Found")
        XCTAssertEqual(HTTPResponse.reason(599), "Status")
    }
}
