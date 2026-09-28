import Foundation

/// Réécrit les chemins relatifs d'une feuille de style du snapshot.
///
/// Les CSS du serveur (ex. `/core/css/server.css`) référencent leurs ressources en relatif
/// (`@import '../../dist/icons.css'`, `url(../img/x.svg)`). Servies depuis `/local/assets/css/`,
/// ces références ne mènent plus nulle part : on les résout par rapport à l'emplacement
/// d'origine (`href` du manifeste) pour obtenir un chemin absolu, relayé vers Nextcloud.
enum CSSPathRewriter {
    /// Version de la réécriture, ajoutée à l'ETag pour invalider le cache WebKit si elle change.
    static let version = "r1"

    private static let urlPattern = try! NSRegularExpression(pattern: #"url\(\s*(['"]?)([^'")]+)\1\s*\)"#)
    private static let importPattern = try! NSRegularExpression(pattern: #"@import\s*(['"])([^'"]+)\1"#)

    static func rewrite(_ data: Data, originalHref: String) -> Data {
        guard var css = String(data: data, encoding: .utf8),
              let base = URL(string: "http://placeholder" + originalHref)
        else { return data }
        for pattern in [urlPattern, importPattern] {
            css = replace(in: css, pattern: pattern, base: base)
        }
        return Data(css.utf8)
    }

    /// Remplace le groupe 2 (la référence) de chaque correspondance, de la fin vers le début.
    private static func replace(in css: String, pattern: NSRegularExpression, base: URL) -> String {
        var result = css
        let matches = pattern.matches(in: css, range: NSRange(css.startIndex..., in: css))
        for match in matches.reversed() {
            guard let range = Range(match.range(at: 2), in: result) else { continue }
            let reference = String(result[range])
            if let absolute = resolve(reference, base: base) {
                result.replaceSubrange(range, with: absolute)
            }
        }
        return result
    }

    /// Chemin absolu pour une référence relative ; `nil` si elle est déjà absolue ou spéciale.
    private static func resolve(_ reference: String, base: URL) -> String? {
        let ref = reference.trimmingCharacters(in: .whitespaces)
        let untouched = ["data:", "http:", "https:", "//", "/", "#", "blob:"]
        guard !ref.isEmpty, !untouched.contains(where: { ref.lowercased().hasPrefix($0) }),
              let resolved = URL(string: ref, relativeTo: base)?.absoluteURL
        else { return nil }
        var path = resolved.path
        if let query = resolved.query { path += "?" + query }
        if let fragment = resolved.fragment { path += "#" + fragment }
        return path
    }
}
