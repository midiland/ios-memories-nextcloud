import Foundation

/// URL d'un serveur Nextcloud, normalisée vers la racine de l'app Memories.
///
/// Reproduit `getMemoriesUrl()` de `welcome.html` (app Android) :
/// `cloud.exemple.fr` → `https://cloud.exemple.fr/index.php/apps/memories/`.
struct ServerURL: Equatable, Codable {
    /// Racine de l'app Memories, toujours terminée par `/`.
    let memoriesURL: URL

    /// Construit l'URL à partir de la saisie utilisateur. `nil` si la saisie est invalide.
    init?(userInput: String) {
        var text = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        // Schéma par défaut : https (comme Android).
        if !text.lowercased().hasPrefix("http://") && !text.lowercased().hasPrefix("https://") {
            text = "https://" + text
        }
        guard var components = URLComponents(string: text),
              let host = components.host, !host.isEmpty
        else { return nil }

        // On ignore requête et fragment éventuellement collés par l'utilisateur.
        components.query = nil
        components.fragment = nil

        var path = components.path
        if !path.hasSuffix("/") { path += "/" }
        if !path.contains("index.php") { path += "index.php/" }
        if !path.contains("apps/memories") { path += "apps/memories/" }
        components.path = path

        guard let url = components.url else { return nil }
        memoriesURL = url
    }

    /// Construit l'URL directement depuis un `baseUrl` renvoyé par le serveur.
    init?(memoriesBaseURL: String) {
        guard var url = URL(string: memoriesBaseURL), url.host != nil else { return nil }
        if !url.absoluteString.hasSuffix("/") {
            url = URL(string: url.absoluteString + "/") ?? url
        }
        memoriesURL = url
    }

    /// Endpoint public `api/describe` de Memories (version, baseUrl, loginFlowUrl, uid).
    var describeURL: URL { memoriesURL.appendingPathComponent("api/describe") }

    /// Racine de Nextcloud (webroot), ex. `https://cloud/` ou `https://exemple.fr/nextcloud/`.
    var nextcloudRoot: URL {
        var text = memoriesURL.absoluteString
        for suffix in ["index.php/apps/memories/", "apps/memories/"] where text.hasSuffix(suffix) {
            text.removeLast(suffix.count)
            break
        }
        return URL(string: text) ?? origin
    }

    /// Hôte du serveur (sert à filtrer cookies et navigations).
    var host: String { memoriesURL.host ?? "" }

    /// Origine `schéma://hôte[:port]` du serveur.
    var origin: URL {
        var components = URLComponents()
        components.scheme = memoriesURL.scheme
        components.host = memoriesURL.host
        components.port = memoriesURL.port
        return components.url ?? memoriesURL
    }
}
