import XCTest
@testable import Memories

final class HTTPRequestParserTests: XCTestCase {
    private func parse(_ text: String, limits: HTTPRequestParser.Limits = .init()) -> HTTPRequestParser.Result {
        HTTPRequestParser.parse(Data(text.utf8), limits: limits)
    }

    private func status(_ result: HTTPRequestParser.Result) -> Int? {
        if case .rejected(let status, _) = result { return status }
        return nil
    }

    func testIncompleteHeadersWait() {
        guard case .incomplete = parse("GET / HTTP/1.1\r\nHost: x\r\n") else { return XCTFail() }
    }

    func testParsesHeadAndBodyLength() throws {
        let result = parse("POST /up HTTP/1.1\r\nHost: x\r\nContent-Length: 4\r\n\r\nabcd")
        guard case .head(let head, let offset, let length) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(head.method, "POST")
        XCTAssertEqual(length, 4)
        XCTAssertEqual(offset, "POST /up HTTP/1.1\r\nHost: x\r\nContent-Length: 4\r\n\r\n".utf8.count)
    }

    func testOffsetIsRelativeToTheBufferStart() {
        let data = Data("junkGET / HTTP/1.1\r\nHost: x\r\n\r\n".utf8).dropFirst(4)
        guard case .head(_, let offset, let length) = HTTPRequestParser.parse(Data(data).dropFirst(0)) else { return XCTFail() }
        XCTAssertEqual(offset, "GET / HTTP/1.1\r\nHost: x\r\n\r\n".utf8.count)
        XCTAssertEqual(length, 0)
    }

    func testRejectsNegativeContentLength() {
        XCTAssertEqual(status(parse("POST / HTTP/1.1\r\nContent-Length: -5\r\n\r\n")), 400)
    }

    func testRejectsMalformedOrRepeatedContentLength() {
        for value in ["abc", "5, 5", "0x10", "+5", " ", "", "1e3", "99999999999999999999", "５"] {
            XCTAssertEqual(status(parse("POST / HTTP/1.1\r\nContent-Length: \(value)\r\n\r\n")), 400, value)
        }
        let repeated = "POST / HTTP/1.1\r\nContent-Length: 5\r\nContent-Length: 7\r\n\r\n"
        XCTAssertEqual(status(parse(repeated)), 400)
    }

    func testRejectsTransferEncoding() {
        XCTAssertEqual(status(parse("POST / HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n")), 411)
    }

    func testRejectsOversizedBody() {
        let limits = HTTPRequestParser.Limits(maxHeaderSize: 1024, maxBodySize: 10)
        XCTAssertEqual(status(parse("POST / HTTP/1.1\r\nContent-Length: 11\r\n\r\n", limits: limits)), 413)
        guard case .head = parse("POST / HTTP/1.1\r\nContent-Length: 10\r\n\r\n", limits: limits) else { return XCTFail() }
    }

    func testRejectsOversizedHeadersWithOrWithoutTerminator() {
        let limits = HTTPRequestParser.Limits(maxHeaderSize: 64, maxBodySize: 10)
        let long = String(repeating: "a", count: 100)
        XCTAssertEqual(status(parse("GET / HTTP/1.1\r\nX: \(long)", limits: limits)), 431)
        XCTAssertEqual(status(parse("GET / HTTP/1.1\r\nX: \(long)\r\n\r\n", limits: limits)), 431)
    }

    func testRejectsMalformedRequestLine() {
        XCTAssertEqual(status(parse("GARBAGE\r\n\r\n")), 400)
    }
}
