import Foundation

/// Async bridge routes (`NAPI` in `src/native/api.ts`, `ApiRouter.kt` on Android).
///
/// Device photos are read-only for now: deletion and upload are not implemented.
@MainActor
struct NativeXLoopbackRouter {
    let share: NativeXShareService
    let photos: NativeXPhotoService
    let serverOrigin: URL

    /// Public form of a link built by the frontend: it runs on the local server, so links to
    /// itself point to `127.0.0.1`; they are moved to the real server origin (same path, since
    /// the local server mirrors the server paths). Other links are returned unchanged.
    func publicURL(_ url: URL) -> URL {
        guard url.host == LocalHTTPServer.host || url.host == "localhost",
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return url }
        components.scheme = serverOrigin.scheme
        components.host = serverOrigin.host
        components.port = serverOrigin.port
        return components.url ?? url
    }

    func handle(method: String, url: URL) async -> NativeXResponse {
        guard method == "GET" || method == "OPTIONS" else { return .error }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let rawPath = components?.percentEncodedPath ?? url.path
        let parts = rawPath.split(separator: "/", omittingEmptySubsequences: true).map(String.init)

        switch parts.first == "api" ? Array(parts.dropFirst()) : parts {
        // Local timeline: device photos without a server copy.
        case ["days"]:
            return .json(await photos.daysJSON())
        case let p where p.count == 2 && p[0] == "days":
            guard let dayId = Int(p[1]) else { return .notFound }
            return .json(await photos.dayJSON(dayId))
        case let p where p.count == 3 && p[0] == "image" && p[1] == "info":
            guard let fileId = Int64(p[2]), let info = await photos.imageInfoJSON(fileId: fileId) else { return .notFound }
            return .json(info)

        // Local deletion: nothing to delete; the frontend shows its own confirmation.
        case let p where p.count == 3 && p[0] == "image" && p[1] == "delete":
            return .json(#"{"confirms":false,"count":0}"#)

        // Link sharing: the URL is double-encoded by the frontend.
        case let p where p.count == 3 && p[0] == "share" && p[1] == "url":
            guard let text = p[2].removingPercentEncoding?.removingPercentEncoding,
                  let target = URL(string: text)
            else { return .error }
            share.shareLink(publicURL(target))
            return .json("{}")

        // Sharing files staged by `setShareBlobs`.
        case ["share", "blobs"]:
            return await share.shareStagedBlobs() ? .json("{}") : .error

        // Device photos opt-in / opt-out (iOS permission prompt on first opt-in).
        case let p where p.count == 3 && p[0] == "config" && p[1] == "allow_media":
            await photos.allowMedia(p[2] == "1")
            return .json(#""done""#)

        case ["assets", "progress"]:
            return .json(#"{"status":"ready","done":0,"total":0,"error":null}"#)

        default:
            // upload/local, login…: not handled (images are served by the local server).
            return .notFound
        }
    }
}
