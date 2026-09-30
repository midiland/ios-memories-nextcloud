import Foundation

/// Async bridge routes (`NAPI` in `src/native/api.ts`, `ApiRouter.kt` on Android).
///
/// Step 2a: no local photos yet (PhotoKit = step 2b), so the "local media" routes
/// return empty results; sharing is fully implemented.
@MainActor
struct NativeXLoopbackRouter {
    let share: NativeXShareService

    func handle(method: String, url: URL) async -> NativeXResponse {
        guard method == "GET" || method == "OPTIONS" else { return .error }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let rawPath = components?.percentEncodedPath ?? url.path
        let parts = rawPath.split(separator: "/", omittingEmptySubsequences: true).map(String.init)

        switch parts.first == "api" ? Array(parts.dropFirst()) : parts {
        // Local timeline: no days / no photos on the device for now.
        case ["days"]:
            return .json("[]")
        case let p where p.count == 2 && p[0] == "days":
            return .json("[]")

        // Local deletion: nothing to delete; the frontend shows its own confirmation.
        case let p where p.count == 3 && p[0] == "image" && p[1] == "delete":
            return .json(#"{"confirms":false,"count":0}"#)

        // Link sharing: the URL is double-encoded by the frontend.
        case let p where p.count == 3 && p[0] == "share" && p[1] == "url":
            guard let text = p[2].removingPercentEncoding?.removingPercentEncoding,
                  let target = URL(string: text)
            else { return .error }
            share.shareLink(target)
            return .json("{}")

        // Sharing files staged by `setShareBlobs`.
        case ["share", "blobs"]:
            return await share.shareStagedBlobs() ? .json("{}") : .error

        // Local media permission: no effect until PhotoKit is wired up.
        case let p where p.count == 3 && p[0] == "config" && p[1] == "allow_media":
            return .json(#""done""#)

        case ["assets", "progress"]:
            return .json(#"{"status":"ready","done":0,"total":0,"error":null}"#)

        default:
            // image/info, image/preview, image/full, upload/local, login…: not handled yet.
            return .notFound
        }
    }
}
