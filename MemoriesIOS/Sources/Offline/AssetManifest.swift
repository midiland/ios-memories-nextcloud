import Foundation

/// Manifests of the Memories web files, extracted from `api/describe?manifest=1`
/// (see `OtherController::describeApi` and `AssetSyncCoordinator.kt` on Android).
///
/// - `jsManifest`, in one of two formats, both Ed25519-signed (see `ManifestVerifier`):
///   - Memories 9: base64-encoded JSON, `{ "<file>.js": { hash (SHA-256), href } }`, signed by `jsManifestSig`;
///   - Memories 10: DSSE envelope over TUF targets (`DSSEEnvelope`, `TUFTargets`);
/// - `cssManifest`: list of the server page's `<link>` tags (`{ rel, href, … }`), unsigned.
struct AssetManifest {
    struct JSAsset {
        let name: String
        let sha256: String
        let href: String
        /// Size in bytes (Memories 10 only).
        let length: Int?
    }

    /// Signed part of the JS manifest. The format is recognized by its shape, never by the
    /// (unsigned) server version: both formats are verified against the same pinned keys.
    enum Signed {
        /// Memories 9: signed manifest bytes and the decoded `jsManifestSig` document.
        case legacy(manifest: Data, signatureDocument: Data?)
        /// Memories 10: DSSE envelope and its TUF targets payload.
        case dsse(DSSEEnvelope, TUFTargets)
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
    let signed: Signed
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

        let jsKey: String
        switch object["jsManifest"] {
        case let envelopeObject as [String: Any]:
            guard let envelope = DSSEEnvelope(envelopeObject),
                  let targets = TUFTargets(payload: envelope.payload),
                  let payloadB64 = envelopeObject["payload"] as? String
            else { throw OfflineError.noManifest }
            signed = .dsse(envelope, targets)
            js = targets.targets.compactMap { target in
                guard Self.isScript(target.name) else { return nil }
                return JSAsset(name: target.name, sha256: target.sha256, href: target.href, length: target.length)
            }.sorted { $0.name < $1.name }
            jsKey = payloadB64

        case let jsB64 as String:
            guard !jsB64.isEmpty,
                  let manifest = Data(base64Encoded: jsB64, options: .ignoreUnknownCharacters),
                  let jsObject = try JSONSerialization.jsonObject(with: manifest) as? [String: Any]
            else { throw OfflineError.noManifest }
            let signatureDocument = (object["jsManifestSig"] as? String)
                .flatMap { Data(base64Encoded: $0, options: .ignoreUnknownCharacters) }
            signed = .legacy(manifest: manifest, signatureDocument: signatureDocument)
            js = jsObject.compactMap { name, value in
                guard Self.isScript(name),
                      let entry = value as? [String: Any],
                      let hash = entry["hash"] as? String, !hash.isEmpty,
                      let href = entry["href"] as? String
                else { return nil }
                return JSAsset(name: name, sha256: hash, href: href, length: nil)
            }.sorted { $0.name < $1.name }
            jsKey = jsB64

        default:
            throw OfflineError.noManifest
        }

        self.raw = raw
        self.describe = describe

        let links = object["cssManifest"] as? [[String: Any]] ?? []
        css = links.enumerated().compactMap { index, link in
            guard let href = link["href"] as? String else { return nil }
            var attributes: [String: String] = [:]
            for (name, value) in link where !(value is NSNull) {
                attributes[name] = (value as? String) ?? "\(value)"
            }
            return CSSAsset(name: Self.cssName(index: index, href: href), href: href, attributes: attributes)
        }

        // Same key as Android: raw JS manifest or DSSE payload (base64) + CSS hrefs in order.
        let keySource = jsKey + "\n" + links.map { ($0["href"] as? String) ?? "" }.joined(separator: "\n")
        key = Data(keySource.utf8).sha256Hex
    }

    /// TUF targets of Memories 10, `nil` for a Memories 9 manifest.
    var targets: TUFTargets? {
        if case .dsse(_, let targets) = signed { return targets }
        return nil
    }

    private static func isScript(_ name: String) -> Bool {
        name.hasSuffix(".js") || name.hasSuffix(".mjs")
    }

    /// `%02d_<basename without query>`, like `AssetCache.cssName` on Android.
    static func cssName(index: Int, href: String) -> String {
        let base = href.split(separator: "/").last.map(String.init) ?? href
        let name = base.split(separator: "?", maxSplits: 1).first.map(String.init) ?? base
        return String(format: "%02d_", index) + name
    }
}
