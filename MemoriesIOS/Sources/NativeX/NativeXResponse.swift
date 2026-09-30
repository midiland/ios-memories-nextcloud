import Foundation

/// Response returned to the JS for an `http://127.0.0.1/...` request.
struct NativeXResponse {
    var status = 200
    var contentType = "application/json"
    var body = "{}"

    /// Format expected by `nativex.js` (`{ status, contentType, body }`).
    var dictionary: [String: Any] {
        ["status": status, "contentType": contentType, "body": body]
    }

    static func json(_ body: String) -> NativeXResponse { NativeXResponse(body: body) }
    static let notFound = NativeXResponse(status: 404)
    static let error = NativeXResponse(status: 500)
}
