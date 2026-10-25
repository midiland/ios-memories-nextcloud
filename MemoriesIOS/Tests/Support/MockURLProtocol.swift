import Foundation

/// A `URLProtocol` that serves canned responses for tests: no real network traffic.
///
/// Register it on a `URLSessionConfiguration` with `config.protocolClasses = [MockURLProtocol.self]`,
/// then set `MockURLProtocol.response` before each call. Reads `httpBodyStream` so POST
/// bodies can be asserted.
final class MockURLProtocol: URLProtocol {
    /// The response to serve for the next request(s). Reset between tests.
    static var response: (data: Data, status: Int, headers: [String: String]) = (.init(), 200, [:])
    /// When set, `startLoading` fails with this error (simulates a network error).
    static var error: Error?
    /// The last request seen by the mock (for assertions on method, path, body, headers).
    static var lastRequest: URLRequest?
    /// The body of the last request, read from `httpBodyStream` if needed.
    static var lastBody: Data?
    /// All requests seen since `reset()`.
    static var requests: [URLRequest] = []

    /// Guards the statics: URLSession calls `startLoading` from its own queue.
    private static let lock = NSLock()

    private static func setLastBody(_ data: Data?) {
        lock.lock()
        lastBody = data
        lock.unlock()
    }

    static func reset() {
        response = (.init(), 200, [:])
        error = nil
        lastRequest = nil
        lastBody = nil
        requests = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let request = self.request
        Self.lock.lock()
        Self.lastRequest = request
        Self.requests.append(request)
        Self.lock.unlock()

        // Read the body: httpBody is nil for streaming requests; httpBodyStream must be read.
        if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var data = Data()
            let bufferSize = 1024
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
            defer { buffer.deallocate() }
            while stream.hasBytesAvailable {
                let read = stream.read(buffer, maxLength: bufferSize)
                if read > 0 {
                    data.append(buffer, count: read)
                } else {
                    break
                }
            }
            Self.setLastBody(data)
        } else {
            Self.setLastBody(request.httpBody)
        }

        if let error = Self.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }

        let (data, status, headers) = Self.response
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://example.com")!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !data.isEmpty {
            client?.urlProtocol(self, didLoad: data)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// A `URLSession` wired to `MockURLProtocol`, for injecting into `NextcloudClient`.
func mockSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: config)
}
