import Foundation

/// Framing of an HTTP/1.1 request in a receive buffer: where the headers end, how long the body is.
/// Pure and strict, because it runs on bytes from any local app before any authentication.
enum HTTPRequestParser {
    struct Limits: Equatable {
        var maxHeaderSize = 64 * 1024
        /// Web uploads go through WebDAV chunks, far below this.
        var maxBodySize = 64 * 1024 * 1024
    }

    enum Result {
        /// The headers are not complete yet.
        case incomplete
        /// Invalid or oversized request: answer with this status and close the connection.
        case rejected(status: Int, message: String)
        /// `bodyOffset` and `contentLength` are relative to `buffer.startIndex`.
        case head(HTTPRequestHead, bodyOffset: Int, contentLength: Int)
    }

    private static let separator = Data("\r\n\r\n".utf8)

    static func parse(_ buffer: Data, limits: Limits = Limits()) -> Result {
        guard let headerEnd = buffer.range(of: separator) else {
            return buffer.count > limits.maxHeaderSize ? .rejected(status: 431, message: "headers too large") : .incomplete
        }
        let bodyOffset = headerEnd.upperBound - buffer.startIndex
        guard bodyOffset <= limits.maxHeaderSize else { return .rejected(status: 431, message: "headers too large") }
        guard let text = String(data: buffer[buffer.startIndex..<headerEnd.lowerBound], encoding: .utf8),
              let head = HTTPRequestHead(text)
        else { return .rejected(status: 400, message: "bad request") }

        if head.headers["transfer-encoding"] != nil { return .rejected(status: 411, message: "length required") }
        guard let length = contentLength(head.headers["content-length"]) else {
            return .rejected(status: 400, message: "bad content-length")
        }
        guard length <= limits.maxBodySize else { return .rejected(status: 413, message: "too large") }
        return .head(head, bodyOffset: bodyOffset, contentLength: length)
    }

    /// `nil` header ⇒ 0. Otherwise ASCII digits only: rejects signs, spaces, hex, and the
    /// `"5, 5"` produced by a repeated header (ambiguous framing, a request smuggling vector).
    static func contentLength(_ value: String?) -> Int? {
        guard let value else { return 0 }
        guard !value.isEmpty, value.utf8.count <= 12, value.utf8.allSatisfy({ (0x30...0x39).contains($0) }) else { return nil }
        return Int(value)
    }
}
