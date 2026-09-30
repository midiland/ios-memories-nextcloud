import CryptoKit
import Foundation
@testable import Memories

/// Shared test data.
enum Fixtures {
    static let server = ServerURL(userInput: "https://cloud.example.com/nextcloud")!
    static let credentials = Credentials(server: server, loginName: "alice", appPassword: "secret")

    /// Seed of the development signing key (`DEFAULT_SEED` in `webpack.manifest-sign-plugin.ts`),
    /// whose public key is `ManifestVerifier.developmentKey`.
    static let developmentSeed = Data(base64Encoded: "BfC97bs84avvLGpUfd0SkOuugTifNffExQ1IS88z58s=")!

    /// JS manifest as published by the server: `{ "<file>": { hash, href } }`.
    static let jsManifest: [String: Any] = [
        "memories-main.js": ["hash": "aa", "href": "/nextcloud/apps/memories/js/memories-main.js"],
        "memories-l10n.js": ["hash": "bb", "href": "/nextcloud/apps/memories/js/memories-l10n.js"],
        "memories-main.js.map": ["hash": "cc", "href": "/nextcloud/apps/memories/js/memories-main.js.map"],
        "no-hash.js": ["href": "/nextcloud/apps/memories/js/no-hash.js"],
    ]

    static let cssManifest: [[String: Any]] = [
        ["rel": "stylesheet", "href": "/nextcloud/core/css/server.css?v=1", "media": "screen"],
        ["rel": "stylesheet", "href": "/nextcloud/apps/memories/css/memories-main.css", "nonce": NSNull()],
    ]

    /// Raw `describe?manifest=1` response, signed with `signingSeed` (unsigned when `nil`).
    static func describe(
        jsManifest: [String: Any] = jsManifest,
        cssManifest: [[String: Any]] = cssManifest,
        signingSeed: Data? = developmentSeed,
        uid: String? = "alice"
    ) throws -> Data {
        let manifestBytes = try JSONSerialization.data(withJSONObject: jsManifest, options: .sortedKeys)
        var object: [String: Any] = [
            "version": "9.1.0",
            "baseUrl": "https://cloud.example.com/nextcloud/index.php/apps/memories/",
            "loginFlowUrl": "https://cloud.example.com/nextcloud/index.php/login/v2",
            "uid": uid ?? NSNull(),
            "jsManifest": manifestBytes.base64EncodedString(),
            "cssManifest": cssManifest,
        ]
        if let signingSeed {
            let key = try Curve25519.Signing.PrivateKey(rawRepresentation: signingSeed)
            let signature = try key.signature(for: manifestBytes)
            let document = try JSONSerialization.data(withJSONObject: ["curve25519": signature.base64EncodedString()])
            object["jsManifestSig"] = document.base64EncodedString()
        }
        return try JSONSerialization.data(withJSONObject: object)
    }

    /// New empty temporary directory, removed by the caller.
    static func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Local server request with the given headers (names are lowercased like the parser does).
    static func request(
        _ target: String, method: String = "GET", headers: [String: String] = [:], version: String = "HTTP/1.1"
    ) -> HTTPRequest {
        HTTPRequest(
            method: method,
            target: target,
            version: version,
            headers: Dictionary(uniqueKeysWithValues: headers.map { ($0.key.lowercased(), $0.value) }),
            body: Data()
        )
    }
}

extension HTTPResponse {
    /// Body of a `.data` response as UTF-8 text.
    var text: String? {
        if case .data(let data) = body { return String(data: data, encoding: .utf8) }
        return nil
    }

    func header(_ name: String) -> String? {
        headers.first { $0.0.caseInsensitiveCompare(name) == .orderedSame }?.1
    }
}
