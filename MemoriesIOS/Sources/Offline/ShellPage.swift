import Foundation

/// Local HTML page that replaces Nextcloud's PHP template (port of `ShellPage.kt`):
/// snapshot stylesheets, l10n, globals expected by the frontend
/// (`_oc_webroot`, `_oc_appswebroots`, `_oc_capabilities`), then `memories-main.js`.
enum ShellPage {
    /// Content-Security-Policy: local scripts + nonce-based inline script, API calls anywhere.
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

    /// Builds the page for a snapshot.
    /// - Parameters:
    ///   - webRoot: Nextcloud prefix (`""` at the domain root, otherwise e.g. `/nextcloud`).
    ///   - user: user ID shown by the frontend (`<head data-user>`).
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
        \(ocGlobal)
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

    /// Minimal `window.OC`, normally defined by the Nextcloud page. `AlbumCollaborators.vue` reads
    /// `window.OC.config[…]` without optional chaining, which breaks the album share and "add
    /// collaborators" dialogs in the native apps (midiland/ios-memories-nextcloud#5, #6; the Android
    /// shell has the same gap). Empty and never replacing an existing object: every `window.OC?.…`
    /// read (including the upstream fix `window.OC?.config?.[…]`) gives the same result as without it.
    /// Reported upstream: pulsejet/memories#1748. Remove once servers ship a Memories version with the fix.
    static let ocGlobal = "window.OC = window.OC || {}; window.OC.config = window.OC.config || {};"

    /// Escaping for an HTML attribute.
    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    /// Single-quoted JS string literal (trusted path, coming from the server).
    private static func jsString(_ text: String) -> String {
        let escaped = text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "<", with: "\\x3c")
        return "'\(escaped)'"
    }
}
