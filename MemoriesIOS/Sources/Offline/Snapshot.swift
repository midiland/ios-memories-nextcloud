import Foundation

/// Snapshot ready to serve: the JS/CSS files of one Memories version.
struct Snapshot {
    let directory: URL
    let manifest: AssetManifest

    var key: String { directory.lastPathComponent }
    var jsDirectory: URL { directory.appendingPathComponent("js", isDirectory: true) }
    var cssDirectory: URL { directory.appendingPathComponent("css", isDirectory: true) }
}
