import CryptoKit
import XCTest
@testable import Memories

final class ManifestVerifierTests: XCTestCase {
    func testDevelopmentKeyMatchesTheWebpackSeed() throws {
        let key = try Curve25519.Signing.PrivateKey(rawRepresentation: Fixtures.developmentSeed)
        XCTAssertEqual(key.publicKey.rawRepresentation.base64EncodedString(), ManifestVerifier.developmentKey)
    }

    func testDevelopmentKeyIsTrustedInDebugOnly() {
        XCTAssertTrue(ManifestVerifier.trustedKeys.contains(ManifestVerifier.productionKey))
        #if DEBUG
        XCTAssertTrue(ManifestVerifier.trustedKeys.contains(ManifestVerifier.developmentKey))
        #else
        XCTAssertFalse(ManifestVerifier.trustedKeys.contains(ManifestVerifier.developmentKey))
        #endif
    }

    #if DEBUG
    func testAcceptsManifestSignedWithDevelopmentKey() throws {
        XCTAssertTrue(ManifestVerifier.verify(try AssetManifest(raw: Fixtures.describe())))
    }
    #endif

    func testRejectsUnknownKey() throws {
        let seed = Curve25519.Signing.PrivateKey().rawRepresentation
        XCTAssertFalse(ManifestVerifier.verify(try AssetManifest(raw: Fixtures.describe(signingSeed: seed))))
    }

    func testRejectsMissingSignature() throws {
        XCTAssertFalse(ManifestVerifier.verify(try AssetManifest(raw: Fixtures.describe(signingSeed: nil))))
    }

    func testRejectsTamperedManifest() throws {
        // Signature of the original manifest, attached to a modified one.
        let signed = try XCTUnwrap(JSONSerialization.jsonObject(with: Fixtures.describe()) as? [String: Any])
        var tampered = Fixtures.jsManifest
        tampered["evil.js"] = ["hash": "dd", "href": "https://evil.example.org/evil.js"]
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Fixtures.describe(jsManifest: tampered, signingSeed: nil)) as? [String: Any]
        )
        object["jsManifestSig"] = signed["jsManifestSig"]
        let raw = try JSONSerialization.data(withJSONObject: object)
        XCTAssertFalse(ManifestVerifier.verify(try AssetManifest(raw: raw)))
    }
}
