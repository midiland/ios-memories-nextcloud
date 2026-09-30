import Foundation

/// Request line and headers of an HTTP/1.1 request (everything before the blank line).
struct HTTPRequestHead {
    let method: String
    let target: String
    let version: String
    /// Headers with lowercased names; repeated headers are joined with `, `.
    let headers: [String: String]

    /// Parses `METHOD target VERSION\r\nName: value\r\n…`. `nil` if the request line is malformed.
    init?(_ text: String) {
        var lines = text.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ").map(String.init)
        guard requestLine.count == 3 else { return nil }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[name] = headers[name].map { "\($0), \(value)" } ?? value
        }
        method = requestLine[0].uppercased()
        target = requestLine[1]
        version = requestLine[2]
        self.headers = headers
    }
}
