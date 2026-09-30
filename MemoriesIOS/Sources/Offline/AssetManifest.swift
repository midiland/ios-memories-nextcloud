import Foundation

/// Manifests of the Memories web files, extracted from `api/describe?manifest=1`
/// (see `OtherController::describeApi` and `AssetSyncCoordinator.kt` on Android).
///
/// - `jsManifest`: base64-encoded JSON, `{ "<file>.js": { hash (SHA-256), href } }`, Ed25519-signed;
/// - `cssManifest`: list of the server page's `<link>` tags (`{ rel, href, … }`), unsigned.
struct AssetManifest {
    struct JSAsset {
        let name: String
        let sha256: String
        let href: String
    }

    struct CSSAsset {
        /// Stable local name: index + remote file name (`03_server.css`).
        let name: String
        let href: String
        /// Attributes to copy onto the local page's `<link>`.
        let attributes: [String: String]
    }

    /// Full `describe` JSON, stored as-is in the snapshot (`describe.json`).
    let raw: Data
    let describe: DescribeResponse
    /// Decoded JS manifest (signed bytes) and signature document.
    let jsManifest: Data
    let signatureDocument: Data?
    let js: [JSAsset]
    let css: [CSSAsset]
    /// Content key: equal ⇔ same files (independent of the version number).
    let key: String

    /// Name of the entry point loaded by the local page; every snapshot must contain it.
    static let entryJS = "memories-main.js"
    static let l10nJS = "memories-l10n.js"

    /// Parses a raw `describe`. Throws `OfflineError.noManifest` if the server provides no manifest.
    init(raw: Data) throws {
        guard let object = try JSONSerialization.jsonObject(with: raw) as? [String: Any],
              let describe = try? JSONDecoder().decode(DescribeResponse.self, from: raw)
        else { throw OfflineError.noManifest }

        guard let jsB64 = object["jsManifest"] as? String, !jsB64.isEmpty,
              let jsManifest = Data(base64Encoded: jsB64, options: .ignoreUnknownCharacters),
              let jsObject = try JSONSerialization.jsonObject(with: jsManifest) as? [String: Any]
        else { throw OfflineError.noManifest }

        self.raw = raw
        self.describe = describe
        self.jsManifest = jsManifest
        signatureDocument = (object["jsManifestSig"] as? String)
            .flatMap { Data(base64Encoded: $0, options: .ignoreUnknownCharacters) }

        js = jsObject.compactMap { name, value in
            guard name.hasSuffix(".js") || name.hasSuffix(".mjs"),
                  let entry = value as? [String: Any],
                  let hash = entry["hash"] as? String, !hash.isEmpty,
                  let href = entry["href"] as? String
            else { return nil }
            return JSAsset(name: name, sha256: hash, href: href)
        }.sorted { $0.name < $1.name }

        let links = object["cssManifest"] as? [[String: Any]] ?? []
        css = links.enumerated().compactMap { index, link in
            guard let href = link["href"] as? String else { return nil }
            var attributes: [String: String] = [:]
            for (name, value) in link where !(value is NSNull) {
                attributes[name] = (value as? String) ?? "\(value)"
            }
            return CSSAsset(name: Self.cssName(index: index, href: href), href: href, attributes: attributes)
        }

        // Same key as Android: raw JS manifest (base64) + CSS hrefs in order.
        let keySource = jsB64 + "\n" + links.map { ($0["href"] as? String) ?? "" }.joined(separator: "\n")
        key = Data(keySource.utf8).sha256Hex
    }

    /// `%02d_<basename without query>`, like `AssetCache.cssName` on Android.
    static func cssName(index: Int, href: String) -> String {
        let base = href.split(separator: "/").last.map(String.init) ?? href
        let name = base.split(separator: "?", maxSplits: 1).first.map(String.init) ?? base
        return String(format: "%02d_", index) + name
    }
}
