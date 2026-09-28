import Foundation

/// Réponse renvoyée au JS pour une requête `http://127.0.0.1/...`.
struct NativeXResponse {
    var status = 200
    var contentType = "application/json"
    var body = "{}"

    /// Format attendu par `nativex.js` (`{ status, contentType, body }`).
    var dictionary: [String: Any] {
        ["status": status, "contentType": contentType, "body": body]
    }

    static func json(_ body: String) -> NativeXResponse { NativeXResponse(body: body) }
    static let notFound = NativeXResponse(status: 404)
    static let error = NativeXResponse(status: 500)
}

/// Routes du pont asynchrone (`NAPI` dans `src/native/api.ts`, `ApiRouter.kt` sur Android).
///
/// Étape 2a : pas encore de photos locales (PhotoKit = étape 2b), donc les routes
/// « médias locaux » répondent vide ; le partage est réellement implémenté.
@MainActor
struct NativeXLoopbackRouter {
    let share: NativeXShareService

    func handle(method: String, url: URL) async -> NativeXResponse {
        guard method == "GET" || method == "OPTIONS" else { return .error }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let rawPath = components?.percentEncodedPath ?? url.path
        let parts = rawPath.split(separator: "/", omittingEmptySubsequences: true).map(String.init)

        switch parts.first == "api" ? Array(parts.dropFirst()) : parts {
        // Timeline locale : aucun jour / aucune photo sur l'appareil pour l'instant.
        case ["days"]:
            return .json("[]")
        case let p where p.count == 2 && p[0] == "days":
            return .json("[]")

        // Suppression locale : rien à supprimer, le frontend affiche sa propre confirmation.
        case let p where p.count == 3 && p[0] == "image" && p[1] == "delete":
            return .json(#"{"confirms":false,"count":0}"#)

        // Partage d'un lien : l'URL est doublement encodée par le frontend.
        case let p where p.count == 3 && p[0] == "share" && p[1] == "url":
            guard let text = p[2].removingPercentEncoding?.removingPercentEncoding,
                  let target = URL(string: text)
            else { return .error }
            share.shareLink(target)
            return .json("{}")

        // Partage de fichiers préparés par `setShareBlobs`.
        case ["share", "blobs"]:
            return await share.shareStagedBlobs() ? .json("{}") : .error

        // Autorisation des médias locaux : sans effet tant que PhotoKit n'est pas branché.
        case let p where p.count == 3 && p[0] == "config" && p[1] == "allow_media":
            return .json(#""done""#)

        case ["assets", "progress"]:
            return .json(#"{"status":"ready","done":0,"total":0,"error":null}"#)

        default:
            // image/info, image/preview, image/full, upload/local, login… : pas encore gérés.
            return .notFound
        }
    }
}
