import Foundation

/// URL of a Nextcloud server, normalized to the root of the Memories app.
///
/// Mirrors `getMemoriesUrl()` from `welcome.html` (Android app):
/// `cloud.exemple.fr` → `https://cloud.exemple.fr/index.php/apps/memories/`.
struct ServerURL: Equatable, Codable {
    /// Root of the Memories app, always ending with `/`.
    let memoriesURL: URL

    /// Builds the URL from user input. `nil` if the input is invalid.
    init?(userInput: String) {
        var text = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        // Default scheme: https (like Android).
        if !text.lowercased().hasPrefix("http://") && !text.lowercased().hasPrefix("https://") {
            text = "https://" + text
        }
        guard var components = URLComponents(string: text),
              let host = components.host, !host.isEmpty
        else { return nil }

        // Ignore any query and fragment pasted by the user.
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

    /// Builds the URL directly from a `baseUrl` returned by the server.
    init?(memoriesBaseURL: String) {
        guard var url = URL(string: memoriesBaseURL), url.host != nil else { return nil }
        if !url.absoluteString.hasSuffix("/") {
            url = URL(string: url.absoluteString + "/") ?? url
        }
        memoriesURL = url
    }

    /// Memories' public `api/describe` endpoint (version, baseUrl, loginFlowUrl, uid).
    var describeURL: URL { memoriesURL.appendingPathComponent("api/describe") }

    /// Nextcloud root (webroot), e.g. `https://cloud/` or `https://exemple.fr/nextcloud/`.
    var nextcloudRoot: URL {
        var text = memoriesURL.absoluteString
        for suffix in ["index.php/apps/memories/", "apps/memories/"] where text.hasSuffix(suffix) {
            text.removeLast(suffix.count)
            break
        }
        return URL(string: text) ?? origin
    }

    /// Nextcloud path prefix without trailing `/`: `""` at the domain root,
    /// otherwise e.g. `/nextcloud` (equivalent of `AssetCache.webrootOf` on Android).
    var webRoot: String {
        var path = nextcloudRoot.path
        while path.hasSuffix("/") { path.removeLast() }
        return path
    }

    /// Server host (used to filter cookies and navigations).
    var host: String { memoriesURL.host ?? "" }

    /// Server origin `scheme://host[:port]`.
    var origin: URL {
        var components = URLComponents()
        components.scheme = memoriesURL.scheme
        components.host = memoriesURL.host
        components.port = memoriesURL.port
        return components.url ?? memoriesURL
    }
}
