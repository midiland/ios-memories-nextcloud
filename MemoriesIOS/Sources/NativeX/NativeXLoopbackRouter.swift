import Foundation

/// Async bridge routes (`NAPI` in `src/native/api.ts`, `ApiRouter.kt` on Android).
///
/// Device photos are read-only for now: deletion and upload are not implemented.
@MainActor
struct NativeXLoopbackRouter {
    let share: NativeXShareService
    let photos: NativeXPhotoService
    let serverOrigin: URL

    /// Replaces localhost (127.0.0.1) URLs with the actual Nextcloud server origin.
    /// This fixes issue #7 where public share links were pointing to the local server
    /// instead of the real Nextcloud server.
    /// https://github.com/midiland/ios-memories-nextcloud/issues/7
    private func replaceLocalhostWithServerOrigin(_ url: URL) -> URL {
        // If the URL already uses the correct server, return as-is
        if url.host == serverOrigin.host && url.scheme == serverOrigin.scheme {
            return url
        }
        
        // If the URL is localhost or 127.0.0.1, replace with serverOrigin
        if url.host == "127.0.0.1" || url.host == "localhost" {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.scheme = serverOrigin.scheme
            components?.host = serverOrigin.host
            components?.port = serverOrigin.port
            if let correctedURL = components?.url {
                return correctedURL
            }
        }
        
        // For relative URLs or other cases, append to serverOrigin
        return serverOrigin.appendingPathComponent(url.absoluteString)
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
            // Fix issue #7: replace localhost with actual server origin
            let correctedTarget = replaceLocalhostWithServerOrigin(target)
            share.shareLink(correctedTarget)
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
