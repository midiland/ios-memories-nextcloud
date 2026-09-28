import Foundation

/// Rewrites relative paths in a snapshot stylesheet.
///
/// Server stylesheets (e.g. `/core/css/server.css`) reference their resources with relative paths
/// (`@import '../../dist/icons.css'`, `url(../img/x.svg)`). When served from `/local/assets/css/`,
/// those references no longer resolve, so we resolve them against the original location
/// (the manifest `href`) to get an absolute path, which is proxied to Nextcloud.
enum CSSPathRewriter {
    /// Rewrite version, appended to the ETag to invalidate the WebKit cache when it changes.
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

    /// Replaces group 2 (the reference) of each match, from last to first.
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

    /// Absolute path for a relative reference; `nil` if it is already absolute or special.
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
