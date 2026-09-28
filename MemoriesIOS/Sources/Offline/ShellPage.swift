import Foundation

/// Page HTML locale qui remplace le template PHP de Nextcloud (port de `ShellPage.kt`) :
/// feuilles de style du snapshot, l10n, variables globales attendues par le frontend
/// (`_oc_webroot`, `_oc_appswebroots`, `_oc_capabilities`), puis `memories-main.js`.
enum ShellPage {
    /// Content-Security-Policy : scripts locaux + script inline à nonce, API partout.
    static func csp(nonce: String) -> String {
        [
            "default-src 'self'",
            "script-src 'self' blob: 'nonce-\(nonce)'",
            "worker-src 'self' blob:",
            "style-src 'self' 'unsafe-inline'",
            "img-src 'self' data: blob: https:",
            "media-src 'self' blob: data:",
            "connect-src 'self' https: http: wss: ws: data: blob:",
            "font-src 'self' data:",
            "frame-src 'self' https://www.openstreetmap.org",
            "object-src 'none'",
            "base-uri 'self'",
            "form-action 'self'",
            "frame-ancestors 'none'",
        ].joined(separator: "; ")
    }

    /// Construit la page pour un snapshot.
    /// - Parameters:
    ///   - webRoot: préfixe Nextcloud (`""` à la racine du domaine, sinon `/nextcloud`).
    ///   - user: identifiant affiché par le frontend (`<head data-user>`).
    static func html(manifest: AssetManifest, webRoot: String, user: String?, nonce: String) -> String {
        let links = manifest.css.map { asset -> String in
            var attributes = asset.attributes
            attributes["href"] = "/local/assets/css/" + asset.name
            if attributes["rel", default: ""].isEmpty { attributes["rel"] = "stylesheet" }
            let rendered = attributes.sorted { $0.key < $1.key }
                .map { "\(escape($0.key))=\"\(escape($0.value))\"" }
                .joined(separator: " ")
            return "<link \(rendered)>"
        }.joined(separator: "\n")

        let root = jsString(webRoot)
        let userAttribute = user.map { " data-user=\"\(escape($0))\"" } ?? ""

        return """
        <!DOCTYPE html>
        <html>
        <head\(userAttribute)>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Memories</title>
        \(links)
        <link href="/local/static/shell-overrides.css" rel="stylesheet">
        <script src="/local/assets/js/\(AssetManifest.l10nJS)"></script>
        </head>
        <body>
        <div id="skip-actions"></div>
        <div id="content"></div>
        <script nonce="\(nonce)">
        window._oc_webroot = \(root); window._oc_appswebroots = {'memories': \(root) + '/apps/memories'};
        window._oc_capabilities = {
          'files': {
            'forbidden_filename_characters': ['/', '\\\\'],
            'forbidden_filenames': ['.htaccess'],
            'forbidden_filename_basenames': [],
            'forbidden_filename_extensions': ['.part', '.filepart']
          }
        };
        </script>
        <script src="/local/assets/js/\(AssetManifest.entryJS)" defer></script>
        </body>
        </html>
        """
    }

    /// Échappement pour un attribut HTML.
    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    /// Littéral de chaîne JS entre apostrophes (chemin de confiance, venant du serveur).
    private static func jsString(_ text: String) -> String {
        let escaped = text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "<", with: "\\x3c")
        return "'\(escaped)'"
    }
}
