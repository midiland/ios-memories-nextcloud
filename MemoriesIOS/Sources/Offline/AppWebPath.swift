import Foundation

/// Where the server actually serves the Memories app's static files.
///
/// The manifest hrefs are fixed at build time (`publicPath: '/apps/memories/js/'` in `webpack.config.ts`):
/// they ignore both the Nextcloud web root (`/nextcloud`) and the apps folder the app is installed in
/// (`custom_apps` on Nextcloud AIO and the Docker image), so they can point to a 404. The real path is
/// the `memories` entry of `_oc_appswebroots` in the server's Memories page, e.g. `/custom_apps/memories`.
/// Only the download location changes: every file is still checked against the signed manifest.
struct AppWebPath: Equatable {
    /// Build-time prefix of the manifest hrefs.
    static let manifestRoot = "/apps/memories"

    /// Path of the Memories app folder on the server, web root included, without trailing `/`.
    let root: String

    /// Default when the page cannot be read: the standard `apps` folder under the web root.
    init(webRoot: String) {
        root = webRoot + Self.manifestRoot
    }

    /// Reads `_oc_appswebroots` from the HTML of the Memories page; `nil` if absent or not a plain path.
    init?(pageHTML html: String) {
        guard let roots = html.range(of: "appswebroots") else { return nil }
        let tail = String(html[roots.upperBound...])
        guard let match = Self.memoriesEntry.firstMatch(in: tail, range: NSRange(tail.startIndex..., in: tail)),
              let value = Range(match.range(at: 1), in: tail)
        else { return nil }
        let root = tail[value].replacingOccurrences(of: "\\/", with: "/")
        guard Self.isPlainPath(root) else { return nil }
        self.root = root
    }

    private static let memoriesEntry = try! NSRegularExpression(pattern: #""memories"\s*:\s*"([^"]+)""#)

    /// Manifest href → path to download: hrefs under `/apps/memories/` are moved to `root`, others unchanged.
    func resolve(_ href: String) -> String {
        guard href.hasPrefix(Self.manifestRoot + "/") else { return href }
        return root + href.dropFirst(Self.manifestRoot.count)
    }

    /// Absolute path made of simple segments: no scheme or host, no `..`, nothing to escape the origin.
    private static func isPlainPath(_ path: String) -> Bool {
        guard path.hasPrefix("/") else { return false }
        let segments = path.split(separator: "/", omittingEmptySubsequences: false).dropFirst()
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        return !segments.isEmpty && segments.allSatisfy { segment in
            !segment.isEmpty && segment != "." && segment != ".."
                && segment.unicodeScalars.allSatisfy { allowed.contains($0) }
        }
    }
}
