import CryptoKit
import Foundation

/// Manifestes des fichiers web de Memories, extraits de `api/describe?manifest=1`
/// (voir `OtherController::describeApi` et `AssetSyncCoordinator.kt` sur Android).
///
/// - `jsManifest` : JSON encodé en base64, `{ "<fichier>.js": { hash (SHA-256), href } }`, signé Ed25519 ;
/// - `cssManifest` : liste des `<link>` de la page serveur (`{ rel, href, … }`), non signée.
struct AssetManifest {
    struct JSAsset {
        let name: String
        let sha256: String
        let href: String
    }

    struct CSSAsset {
        /// Nom local stable : index + nom de fichier distant (`03_server.css`).
        let name: String
        let href: String
        /// Attributs à recopier sur le `<link>` de la page locale.
        let attributes: [String: String]
    }

    /// JSON `describe` complet, conservé tel quel dans le snapshot (`describe.json`).
    let raw: Data
    let describe: DescribeResponse
    /// Manifeste JS décodé (octets signés) et document de signature.
    let jsManifest: Data
    let signatureDocument: Data?
    let js: [JSAsset]
    let css: [CSSAsset]
    /// Clé de contenu : identique ⇔ mêmes fichiers (indépendante du numéro de version).
    let key: String

    /// Nom du point d'entrée chargé par la page locale ; tout snapshot doit le contenir.
    static let entryJS = "memories-main.js"
    static let l10nJS = "memories-l10n.js"

    /// Analyse un `describe` brut. Lève `OfflineError.noManifest` si le serveur n'en fournit pas.
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

        // Même clé qu'Android : manifeste JS brut (base64) + hrefs CSS dans l'ordre.
        let keySource = jsB64 + "\n" + links.map { ($0["href"] as? String) ?? "" }.joined(separator: "\n")
        key = SHA256.hash(data: Data(keySource.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// `%02d_<basename sans requête>`, comme `AssetCache.cssName` sur Android.
    static func cssName(index: Int, href: String) -> String {
        let base = href.split(separator: "/").last.map(String.init) ?? href
        let name = base.split(separator: "?", maxSplits: 1).first.map(String.init) ?? base
        return String(format: "%02d_", index) + name
    }
}

/// Erreurs propres au mode hors ligne (toutes provoquent un repli sur le chargement distant).
enum OfflineError: Error {
    case noManifest
    case badSignature
    case integrity(String)
    case download(String, Int)
}
